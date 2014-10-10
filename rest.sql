-- JSON HTTP SQL REST interface
CREATE SCHEMA rest;
SET search_path TO rest, public;

-- HTTP methods
CREATE TYPE method AS ENUM ('get', 'post', 'put', 'delete');

-- SQL error
CREATE TYPE error AS (
  state       text, -- SQL error code
  message     text  -- SQL error message
);

-- REST request
CREATE TYPE request AS (
  body        json, -- JSON payload
  session     json, -- HTTP session with user, roles and expiration
  params      json  -- HTTP route params
);

-- REST response
CREATE TYPE response AS (
  code        int, -- HTTP status code like 201, 404, 500
  data        json -- JSON result object or error message
);

-- HTTP response
CREATE TYPE http_response AS (
  code        int,  -- HTTP status code like 201, 404, 500
  session     json, -- HTTP session with user, roles and expiration
  data        json  -- JSON result object or error message
);

-- application role
CREATE TYPE arole AS ENUM ('admin', 'every', 'user');

-- application user
CREATE TABLE auser (
  id          serial  PRIMARY KEY,
  login       text    NOT NULL,
  http_basic  text    NOT NULL,
  roles       arole[] NOT NULL,
  description text    NOT NULL,
  UNIQUE (login)
);

-- application session
CREATE TABLE asession (
  id      serial    PRIMARY KEY,
  user_id int       NOT NULL REFERENCES auser,
  session uuid      NOT NULL DEFAULT uuid_generate_v4(),
  expires timestamp NOT NULL DEFAULT now() + INTERVAL '37 minute',
  UNIQUE (session)
);

-- HTTP route
CREATE TABLE route (
  id          serial PRIMARY KEY,
  method      method  NOT NULL DEFAULT 'get',
  path        text    NOT NULL, -- request path with params
  proc        text    NOT NULL, -- function to call
  legitimate  arole[] NOT NULL DEFAULT '{"every"}', -- restrict access
  description text    NOT NULL,
  params      text[]  NOT NULL, -- param array (extracted from path)
  match       text    NOT NULL, -- prepared regexp match
  UNIQUE (method, path)
);

-- template mapping
CREATE TABLE template (
  id     serial PRIMARY KEY,
  proc   text   NOT NULL, -- SQL function
  mime   text   NOT NULL, -- mime type
  path   text   NOT NULL, -- template file path
  locals json   NOT NULL, -- default template values like the title of a HTML template
  UNIQUE (mime, path)
);

-- create an user with roles and HTTP Basic Auth encoded password
CREATE FUNCTION add_user(u_login text, u_password text, u_desc text, u_roles arole[])
  RETURNS auser AS $$ DECLARE u auser;
  BEGIN
    INSERT INTO auser (login, http_basic, description, roles)
    VALUES (u_login, encode(concat_ws(':', u_login, u_password)::bytea, 'base64'), u_desc, u_roles) RETURNING * INTO u;
    RETURN u;
  END;
$$ LANGUAGE plpgsql;

-- serialize session and user data
CREATE FUNCTION json_build_session(s asession, u auser)
  RETURNS json AS $$
  BEGIN
    RETURN json_build_object(
      'id', s.session
    , 'expires', s.expires
    , 'epoch', EXTRACT(EPOCH FROM s.expires)::int
    , 'user', u.login
    , 'roles', u.roles);
  END;
$$ LANGUAGE plpgsql;

-- prepare route path matches
CREATE FUNCTION route_path_match()
  RETURNS trigger AS $$ DECLARE path text; params text[];
  BEGIN
    IF TG_TABLE_NAME = 'route' AND (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
      path := replace(NEW.path, '?', '\?');
      SELECT COALESCE(array_agg(m[1]), '{}') FROM regexp_matches(path, '{(\w+)}', 'g') m INTO params;
      NEW.params := params;
      NEW.match := '^'||regexp_replace(path, '({\w+})', '(\w+)', 'g')||'$';
      RETURN NEW;
    ELSE
      RAISE 'invalid route_path_match() call: % % %', TG_TABLE_NAME, TG_OP, NEW;
      RETURN NULL;
    END IF;
  END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER route_path_match BEFORE INSERT OR UPDATE ON route FOR EACH ROW EXECUTE PROCEDURE route_path_match();

-- route an endpoint call
CREATE FUNCTION public.call(c_method text, c_path text, c_session uuid, body json)
  RETURNS http_response AS $$
  DECLARE
    authorized boolean := false;
    r route; s asession; u auser;
    res response; req request;
    pns text[]; pvs text[]; rs json;
  BEGIN
    -- update session and fetch user
    IF c_session IS NOT NULL THEN
      UPDATE asession SET expires = now() + INTERVAL '37 minute'
      WHERE session = c_session AND expires > now() RETURNING * INTO s;
      SELECT * FROM auser WHERE id = s.user_id INTO u;
    END IF;

    -- map session and user
    IF s IS NOT NULL THEN
      rs = json_build_session(s, u);
    END IF;

    -- fetch route
    SELECT * FROM route WHERE method = c_method::method AND c_path ~ match INTO STRICT r;
    IF r.legitimate @> '{"every"}' THEN
      authorized := true;
    ELSE -- authorize
      IF s IS NULL THEN -- not authenticated
        RETURN (401, rs, to_json(('unauthenticated', 'authentication required')::error));
      ELSE
        IF r.legitimate && u.roles THEN -- authorized
          authorized := true;
        END IF;
      END IF;
    END IF;

    IF NOT authorized THEN
      RETURN (403, rs, to_json(('forbidden', 'authorization required')::error));
    ELSE
      -- map param names and values
      IF array_length(r.params, 1) IS NULL THEN
        req := (body, rs, '{}'::json); -- empty params
      ELSE
        SELECT regexp_matches(c_path, r.match) INTO pvs;
        req := (body, rs, json_object(r.params, pvs));
      END IF;
      -- execute authorized function call
      EXECUTE 'SELECT * FROM '||quote_ident(r.proc)||'($1)' USING req INTO STRICT res;
      RETURN (res.code, rs, res.data);
    END IF;
  EXCEPTION
    WHEN no_data_found THEN RETURN (404, rs, to_json((SQLSTATE, SQLERRM)::error));
    WHEN OTHERS THEN RETURN (500, rs, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql
   -- This grants the access to all published routes!
   SECURITY DEFINER;

-- template path lookup
CREATE FUNCTION public.find_template(r_mime text, r_path text, OUT path text, OUT locals json)
  AS $$ DECLARE r route; t template;
  BEGIN
    SELECT * FROM route WHERE 'get' = method AND r_path ~ match INTO STRICT r;
    SELECT * FROM template WHERE r_mime = mime AND r.proc = proc INTO STRICT t;
    path := t.path;
    locals := t.locals;
  EXCEPTION WHEN no_data_found THEN path := NULL;
  END;
$$ LANGUAGE plpgsql
   -- Export access for all!
   SECURITY DEFINER;

-- call a GET route
CREATE FUNCTION get(path text, session uuid)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('get', path, session, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get(path text)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('get', path, NULL, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

-- call a POST route
CREATE FUNCTION post(path text, session uuid, body json)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('post', path, session, body);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post(path text, body json)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('post', path, NULL, body);
  END;
$$ LANGUAGE plpgsql;

-- call a POST route without body
CREATE FUNCTION post(path text, session uuid)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('post', path, session, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post(path text)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('post', path, NULL, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

-- call a PUT route
CREATE FUNCTION put(path text, session uuid, body json)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('put', path, session, body);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION put(path text, body json)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('put', path, NULL, body);
  END;
$$ LANGUAGE plpgsql;

-- call a DELETE route
CREATE FUNCTION delete(path text, session uuid)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('delete', path, session, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete(path text)
  RETURNS http_response AS $$
  BEGIN
    RETURN call('delete', path, NULL, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

-- create a route action URI with params
CREATE FUNCTION route_action(m method, a_proc text, a_params text[])
  RETURNS text AS $$ DECLARE r route; path text; param text; i int;
  BEGIN
    SELECT * FROM route
    WHERE m = method
      AND a_proc = proc
      AND array_length(a_params, 1) = array_length(params, 1)
    INTO STRICT r;
    path := r.path;
    FOR i IN array_lower(a_params, 1) .. array_upper(a_params, 1)
    LOOP -- replace all params by key
      path := regexp_replace(path, '({'||r.params[i]||'})', a_params[i]);
    END LOOP;
    RETURN path;
  END;
$$ LANGUAGE plpgsql;

-- create a route action URI without params
CREATE FUNCTION route_action(m method, a_proc text)
  RETURNS text AS $$ DECLARE r route; path text;
  BEGIN
    SELECT * FROM route
    WHERE m = method
      AND a_proc = proc
      AND array_length(params, 1) IS NULL
    INTO STRICT r;
    RETURN r.path;
  END;
$$ LANGUAGE plpgsql;

-- API routes
INSERT INTO route (method, path, proc, legitimate, description) VALUES
('get' , '/login'    , 'form_login'   , '{"every"}', 'login form'),
('get' , '/routes'   , 'get_routes'   , '{"admin"}', 'list all published routes'),
('get' , '/templates', 'get_templates', '{"admin"}', 'list all published templates');

-- API templates
INSERT INTO template (proc, mime, path, locals) VALUES
('form_login'   , 'html', 'login.html'         , '{"title":"Login"}'::json),
('get_routes'   , 'html', 'rest/routes.html'   , '{"title":"Public routes API"}'::json),
('get_templates', 'html', 'rest/templates.html', '{"title":"Published templates"}'::json);

-- HTTP Basic authentication request
CREATE FUNCTION public.login(u_login text, u_basic_auth text)
  RETURNS http_response AS $$ DECLARE s asession; u auser;
  BEGIN
    SELECT * FROM auser WHERE login = u_login AND http_basic = u_basic_auth INTO STRICT u;
    INSERT INTO asession (user_id) VALUES (u.id) RETURNING * INTO STRICT s;
    RETURN (200, json_build_session(s, u), json_build_object('notice', json_build_object('level', 'info', 'message', 'logged in')));
  EXCEPTION
    WHEN no_data_found THEN
      RAISE NOTICE 'login failed %', to_json((SQLSTATE, SQLERRM)::error);
      RETURN (400, 'null'::json, to_json((400, 'login failed')::error));
  END;
$$ LANGUAGE plpgsql
   -- Everybody can try to login!
   SECURITY DEFINER;

-- HTML form login post request
CREATE FUNCTION public.post_login(u_login text, u_password text)
  RETURNS http_response AS $$ DECLARE res http_response;
  BEGIN
    SELECT * FROM login(u_login, encode(concat_ws(':', u_login, u_password)::bytea, 'base64')) INTO res;
    RETURN res;
  END;
$$ LANGUAGE plpgsql
   -- Everybody can try to login!
   SECURITY DEFINER;

-- HTML login form
CREATE FUNCTION form_login(req request)
  RETURNS response AS $$
  BEGIN
    RETURN (200, json_build_object('placeholder', json_build_object('login', 'user name', 'password', 'your complex passphrase')));
  END;
$$ LANGUAGE plpgsql;

-- auth logout request
CREATE FUNCTION logout(c_session uuid)
  RETURNS asession AS $$ DECLARE s asession;
  BEGIN
    DELETE FROM asession WHERE session = c_session RETURNING * INTO STRICT s;
    RETURN s;
  END;
$$ LANGUAGE plpgsql;

-- HTTP auth logout request
CREATE FUNCTION public.post_logout(c_session uuid)
  RETURNS response AS $$
  BEGIN
    PERFORM logout(c_session);
    RETURN (200, json_build_object(
      'notice', json_build_object('level', 'info', 'message', 'logged out')
    , 'routes', json_build_object('login', route_action('get', 'form_login')))
    );
  EXCEPTION
    WHEN no_data_found THEN
      RAISE NOTICE 'logout failed %', to_json((SQLSTATE, SQLERRM)::error);
      RETURN (400, to_json((400, 'logout failed')::error))::response;
  END;
$$ LANGUAGE plpgsql
   -- Everybody can try a logout!
   SECURITY DEFINER;

-- list all routes
CREATE FUNCTION get_routes(req request)
  RETURNS response AS $$ DECLARE routes json;
  BEGIN
    SELECT json_agg(json_build_object(
      'path', r.path
    , 'method', r.method
    , 'proc', r.proc
    , 'params', r.params
    , 'description', r.description)
    ORDER BY r.path, r.method)
    FROM route r INTO routes;
    RETURN (200, json_build_object('routes', routes));
  END;
$$ LANGUAGE plpgsql;

-- list all templates
CREATE FUNCTION get_templates(req request)
  RETURNS response AS $$ DECLARE templates json;
  BEGIN
    WITH template_list AS (
      SELECT t.*, json_agg(json_build_object(
        'method', r.method
      , 'params', r.params
      , 'path', r.path)
      ORDER BY r.method, r.path) AS routes
      FROM template t
      JOIN route r ON r.proc = t.proc
      GROUP BY t.id
    )
    SELECT json_agg(json_build_object(
      'path', path
    , 'proc', proc
    , 'mime', mime
    , 'locals', locals
    , 'routes', routes)
    ORDER BY t.path, t.mime)
    FROM template_list t INTO templates;
    RETURN (200, json_build_object('templates', templates));
  END;
$$ LANGUAGE plpgsql;

