-- specifications
SET search_path TO dashboard, tasks, contacts, rest, public;

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;          -- an JSON object
    sid uuid;          -- an user sesssion
    res http_response; -- a function result
  BEGIN

    BEGIN
      RAISE INFO 'create test data';
      PERFORM create_contact('Danny Gräf', 'Auf der Wiese 17', '12372', 'Berlin');
      PERFORM create_task('keep on going', 'live every day to its fullest');
      PERFORM add_user('icke', 'secret', 'test administrator', '{"admin", "user"}');
      PERFORM add_user('er', 'secret', 'test user', '{"user"}');
    END;

    -- TEST SQL template function
    BEGIN
      RAISE INFO 'find tasks HTML template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('html', '/tasks') INTO STRICT ref;
      IF ref->>'path' = 'tasks/index.html' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'tasks HTML template expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'find tasks SVG template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('svg', '/tasks?status=test') INTO STRICT ref;
      IF ref->>'path' = 'tasks/stats.svg' THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'tasks SVG template expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'find an unknown template';
      SELECT json_build_object('path', path) FROM find_template('html', '/unknown') INTO STRICT ref;
      IF (ref->>'path') IS NULL THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'NULL expected, got: %', ref;
      END IF;
    END;

    -- TEST auth functions
    BEGIN
      RAISE INFO 'login with invalid credentials';
      PERFORM login('unknown', 'secret');
      EXCEPTION WHEN no_data_found THEN RAISE INFO 'OK: login failed';
    END;

    BEGIN
      RAISE INFO 'login as admin';
      SELECT * FROM login('icke', encode('icke:secret', 'base64')) INTO STRICT res;
      IF res.code = 200 AND length(res.session->>'id') = 36 AND res.data->'notice'->>'level' = 'info' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'session expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    -- reference admin session
    sid := res.session->>'id';

    -- TEST API routes
    BEGIN
      RAISE INFO 'GET 200 /routes';
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 200 AND json_array_length(res.data->'routes') > 0 THEN
        RAISE INFO 'OK: % routes', json_array_length(res.data->'routes');
      ELSE
        RAISE 'route list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 401 /routes unauthenticated';
      SELECT * FROM get('/routes') INTO STRICT res;
      IF res.code = 401 AND res.data->>'state' = 'unauthenticated' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'authentication fail expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 401 /routes expired';
      -- update session expiration
      UPDATE asession SET expires = now() - INTERVAL '1 minute' WHERE session = sid;
      -- use expired session
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 401 AND res.data->>'state' = 'unauthenticated' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'expiration fail expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'logout admin session';
      SELECT to_json(logout(sid)) INTO STRICT ref;
      IF length(ref->>'session') = 36 THEN
        RAISE INFO 'OK: %', ref;
      ELSE
        RAISE 'session expected, got: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /login form';
      SELECT * FROM get('/login') INTO STRICT res;
      IF res.code = 200 AND json_typeof(res.data->'placeholder') = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'login form expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 400 /postlogin';
      SELECT * FROM post_login('unknown', 'secret') INTO STRICT res;
      IF res.code = 400 AND json_typeof(res.data) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'invalid login expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /postlogin as user';
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
      RAISE INFO 'GET 403 /routes';
      SELECT * FROM get('/routes', sid) INTO STRICT res;
      IF res.code = 403 AND res.data->>'state' = 'forbidden' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'forbidden access expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- TEST CRUDL task routes
    BEGIN
      RAISE INFO 'POST 400 /task';
      SELECT * FROM post('/task', sid, '{"subject": "to", "description": "do"}'::json) INTO res;
      IF res.code != 400 THEN
        RAISE 'bad request expected, got: % %', res.code, res.data;
      ELSIF res.data->>'message' !~ 'task_subject_check' THEN
        RAISE 'subject violation expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 201 /task';
      SELECT * FROM post('/task', sid, '{"subject": "todo", "description": "something"}'::json) INTO res;
      IF res.code = 201 AND res.data->>'subject' = 'todo' AND res.data->>'status' = 'open' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'open task expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- remember task data
    ref := res.data;

    BEGIN
      RAISE INFO 'GET 200 /task/{id}';
      SELECT * FROM get('/task/'||(ref->>'id'), sid) INTO res;
      IF res.code = 200 AND res.data->'task'->>'id' = ref->>'id' AND (res.session->>'id')::uuid = sid THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'task details expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'PUT 404 /task';
      SELECT * FROM put('/task/'||nextval('task_id_seq'), sid, '{"subject":123}'::json) INTO res;
      IF res.code = 404 AND (res.session->>'id')::uuid = sid THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'not found expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'PUT 200 /task';
      SELECT * FROM put('/task/'||(ref->>'id'), sid, '{"subject": "todo", "description": "something else"}'::json) INTO res;
      IF res.code = 200 AND (res.data->'task'->>'description') = 'something else' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'updated task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'done' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'finished task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 405 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish', sid) INTO res;
      IF res.code = 405 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'method not allowed, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 405 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel', sid) INTO res;
      IF res.code = 405 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'method not allowed, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 404 /task/{id}/reopen';
      SELECT * FROM post('/task/'||nextval('task_id_seq')||'/reopen', sid) INTO res;
      IF res.code = 404 THEN
        RAISE INFO 'OK:  % %', res.code, res.data;
      ELSE
        RAISE 'not found expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/reopen';
      SELECT * FROM post('/task/'||(ref->>'id')||'/reopen', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'open' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'reopened task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'cancelled' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'cancelled task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks';
      SELECT * FROM get('/tasks') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 2 THEN
        RAISE INFO '% %', res.code, res.data;
      ELSE
        RAISE 'task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks?status=open';
      SELECT * FROM get('/tasks?status=open') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 1 THEN
        RAISE INFO '% %', res.code, res.data;
      ELSE
        RAISE 'open task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks?status=done';
      SELECT * FROM get('/tasks?status=done') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 0 THEN
        RAISE INFO '% %', res.code, res.data;
      ELSE
        RAISE 'empty open task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'DELETE 204 /task';
      SELECT * FROM delete('/task/'||(ref->>'id'), sid) INTO res;
      IF res.code = 204 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'no content expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- TEST CRUDL contact routes
    BEGIN
      RAISE INFO 'POST 400 /contact';
      SELECT * FROM post('/contact', '{"name": "cname", "street": "astreet", "zip": "invalid", "city": "acity"}'::json) INTO res;
      IF res.code != 400 THEN
        RAISE 'bad request expected, got: % %', res.code, res.data;
      ELSIF res.data->>'message' !~ 'address_zip_check' THEN
        RAISE 'zipcode violation expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 201 /contact';
      SELECT * FROM post('/contact', '{"name": "cname", "street": "astreet", "zip": 12345, "city": "acity"}'::json) INTO res;
      IF res.code = 201 AND res.data->>'name' = 'cname' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact record expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- reference the new contact
    ref := res.data;

    BEGIN
      RAISE INFO 'PUT 200 /contact/{id}';
      SELECT * FROM put('/contact/'||(ref->>'id'), '{"name": "cname", "comment": "some notes"}'::json) INTO res;
      IF res.code = 200 AND res.data->>'comment' = 'some notes' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact update expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /contact/{id}';
      SELECT * FROM get('/contact/'||(ref->>'id')) INTO res;
      IF res.code = 200 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- build an address update
    ref := json_build_object('street', 'nstreet', 'zip', '98765', 'city', 'ncity');

    BEGIN
      RAISE INFO 'PUT 200 /contact/{id}/address';
      SELECT * FROM put('/contact/'||(res.data->>'id')||'/address', ref) INTO res;
      IF res.code = 200 AND res.data->>'zip' = '98765' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'address update expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /contacts';
      SELECT * FROM get('/contacts') INTO res;
      IF res.code = 200 AND json_array_length(res.data) = 2 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'DELETE 204 /contact';
      SELECT * FROM delete('/contact/'||(res.data->1->>'id')) INTO res;
      IF res.code = 204 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'no content expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- TEST dashboard
    BEGIN
      RAISE INFO 'GET 200 /';
      SELECT * FROM get('/') INTO res;
      IF res.code = 200 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'dashboard content expected, got: % %', res.code, res.data;
      END IF;
    END;

  RAISE INFO 'OK ;-)';
  END;
$$;
ROLLBACK;

