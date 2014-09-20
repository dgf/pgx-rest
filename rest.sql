-- JSON HTTP SQL REST interface

-- HTTP methods
CREATE TYPE method AS ENUM ('get', 'post', 'put', 'delete');

-- SQL error
CREATE TYPE error AS (
  state       text, -- SQL error code
  message     text  -- SQL error message
);

-- HTTP request
CREATE TYPE request AS (
  params      json, -- HTTP route params
  body        json  -- JSON payload
);

-- HTTP response
CREATE TYPE response AS (
  code        int,  -- HTTP status code like 201, 404, 500
  data        json  -- JSON result object or error message
);

-- HTTP route
CREATE TABLE route (
  id          serial PRIMARY KEY,
  method      method NOT NULL DEFAULT 'get',
  path        text   NOT NULL, -- request path with params
  proc        text   NOT NULL, -- function to call
  description text   NOT NULL,
  params      text[] NOT NULL, -- param array (extracted from path)
  match       text   NOT NULL  -- prepared regexp match
);

-- template mapping
CREATE TABLE template (
  id     serial PRIMARY KEY,
  proc   text   NOT NULL, -- SQL function
  mime   text   NOT NULL, -- mime type
  path   text   NOT NULL, -- template file path
  locals json   NOT NULL  -- default template values like the title of a HTML template
);

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
CREATE FUNCTION call(m method, c_path text, body json)
  RETURNS response AS $$ DECLARE r route; res response; req request; pns text[]; pvs text[];
  BEGIN
    SELECT * FROM route WHERE m = method AND c_path ~ match INTO STRICT r;
    IF array_length(r.params, 1) IS NULL THEN
      req := ('{}'::json, body);
    ELSE
      SELECT regexp_matches(c_path, r.match) INTO pvs;
      req := (json_object(r.params, pvs), body);
    END IF;
    EXECUTE 'SELECT * FROM '||quote_ident(r.proc)||'($1)' USING req INTO STRICT res;
    RETURN res;
  EXCEPTION
    WHEN no_data_found THEN RETURN (404, to_json((SQLSTATE, SQLERRM)::error));
    WHEN OTHERS THEN RETURN (500, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql
   -- This grants the access to all published routes!
   SECURITY DEFINER;

-- template path lookup
CREATE FUNCTION find_template(r_mime text, r_path text, OUT path text, OUT locals json)
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
CREATE FUNCTION get(path text)
  RETURNS response AS $$
  BEGIN
    RETURN call('get'::method, path, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

-- call a POST route
CREATE FUNCTION post(path text, body json)
  RETURNS response AS $$
  BEGIN
    RETURN call('post'::method, path, body);
  END;
$$ LANGUAGE plpgsql;

-- call a POST route without body
CREATE FUNCTION post(path text)
  RETURNS response AS $$
  BEGIN
    RETURN call('post'::method, path, '{}'::json);
  END;
$$ LANGUAGE plpgsql;

-- call a PUT route
CREATE FUNCTION put(path text, body json)
  RETURNS response AS $$
  BEGIN
    RETURN call('put'::method, path, body);
  END;
$$ LANGUAGE plpgsql;

-- call a DELETE route
CREATE FUNCTION delete(path text)
  RETURNS response AS $$
  BEGIN
    RETURN call('delete'::method, path, '{}'::json);
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
INSERT INTO route (method, path, proc, description) VALUES
('get', '/routes', 'get_routes', 'list all published routes'),
('get', '/templates', 'get_templates', 'list all published templates');

-- API templates
INSERT INTO template (proc, mime, path, locals) VALUES
('get_routes'   , 'html', 'rest/routes.html', '{"title":"Public routes API"}'::json),
('get_templates', 'html', 'rest/templates.html', '{"title":"Published templates"}'::json);

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

