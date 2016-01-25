-- REST API specification

-- requires all module paths of rest.globals() call
SET search_path TO application, tasks, contacts, files, rest, public;

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;          -- an JSON object
    sid uuid;          -- an user session
    res http_response; -- a function result
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: REST interface';
    END;

    -- TEST SQL template function
    BEGIN
      RAISE INFO 'TEST: find tasks HTML template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('html', '/tasks') INTO STRICT ref;
      IF ref->>'path' = 'tasks/index.html' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'tasks HTML template expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: find tasks SVG template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('svg', '/tasks?status=test') INTO STRICT ref;
      IF ref->>'path' = 'tasks/stats.svg' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'tasks SVG template expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: find an unknown template';
      SELECT json_build_object('path', path) FROM find_template('html', '/unknown') INTO STRICT ref;
      IF (ref->>'path') IS NULL THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'NULL expected, got: %', ref;
      END IF;
    END;

    -- TEST auth functions
    BEGIN
      RAISE INFO 'TEST: login with invalid credentials';
      SELECT * FROM login('unknown', encode('unknown:secret', 'base64')) INTO STRICT res;
      IF res.code = 400
        AND json_typeof(res.data) = 'object'
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'bad request expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: login as admin';
      SELECT * FROM login('icke', encode('icke:secret', 'base64')) INTO STRICT res;
      IF res.code = 200
        AND length(res.session->>'id') = 36
        AND res.data->'notice'->>'level' = 'info'
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'session expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    -- reference admin session
    sid := res.session->>'id';

    -- TEST API routes
    BEGIN
      RAISE INFO 'TEST: GET 200 /routes';
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 200
        AND json_array_length(res.data->'routes') > 0
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % routes', json_array_length(res.data->'routes');
      ELSE
        RAISE 'route list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 401 /routes unauthenticated';
      SELECT * FROM get('/routes') INTO STRICT res;
      IF res.code = 401
        AND res.data->>'state' = 'unauthenticated'
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'authentication fail expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 401 /routes expired';
      -- update session expiration
      UPDATE asession SET expires = now() - INTERVAL '1 minute' WHERE session = sid;
      -- use expired session
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 401
        AND res.data->>'state' = 'unauthenticated'
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'expiration fail expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: logout admin session';
      SELECT to_json(logout(sid)) INTO STRICT ref;
      IF length(ref->>'session') = 36 THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'session expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /login form';
      SELECT * FROM get('/login') INTO STRICT res;
      IF res.code = 200 AND json_typeof(res.data->'placeholder') = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'login form expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 400 /authenticate';
      SELECT * FROM post_login('unknown', 'secret') INTO STRICT res;
      IF res.code = 400 AND json_typeof(res.data) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'invalid login expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /authenticate as user';
      SELECT * FROM post_login('er', 'secret') INTO STRICT res;
      IF res.code = 200 AND res.session->>'user' = 'er' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'session expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    -- reference user session
    sid := res.session->>'id';

    BEGIN
      RAISE INFO 'TEST: GET 403 /routes';
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 403
        AND res.data->>'state' = 'forbidden'
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'forbidden access expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 400 /logout';
      SELECT json_build_object('code', code, 'data', data) FROM post_logout(NULL::uuid) INTO STRICT ref;
      IF (ref->>'code')::int = 400 AND json_typeof(ref->'data') = 'object' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'bad logout expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /logout';
      SELECT json_build_object('code', code, 'data', data) FROM post_logout(sid) INTO STRICT ref;
      IF (ref->>'code')::int = 200 AND json_typeof(ref->'data'->'notice') = 'object' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'logout expected, got: %', ref;
      END IF;
    END;
  END;
$$;
ROLLBACK;

