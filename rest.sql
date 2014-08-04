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
  code        int, -- HTTP status code like 201, 404, 500
  data        json -- JSON result object or error message
);

-- HTTP route
CREATE TABLE route (
  id          serial PRIMARY KEY,
  method      method NOT NULL DEFAULT 'get',
  path        text   NOT NULL,
  proc        text   NOT NULL,
  description text   NOT NULL,
  params      text[] NOT NULL,
  match       text   NOT NULL
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
    WHEN OTHERS THEN RETURN (500, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

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

