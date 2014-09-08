-- specifications

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;     -- an JSON object
    res response; -- a function result
  BEGIN

    BEGIN
      RAISE INFO 'create test data';
      PERFORM create_contact('Danny Gräf', 'Auf der Wiese 17', '12372', 'Berlin');
      PERFORM create_task('keep on going', 'live every day to its fullest');
    END;

    -- TEST SQL template function
    BEGIN
      RAISE INFO 'find tasks HTML template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('html', '/tasks') INTO ref;
      IF ref->>'path' != 'tasks/index.html' THEN
        RAISE 'tasks HTML template expected, got: %', ref;
      ELSE
        RAISE INFO 'OK: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'find tasks SVG template';
      SELECT json_build_object('path', path, 'locals', locals) FROM find_template('svg', '/tasks?status=test') INTO ref;
      IF ref->>'path' != 'tasks/stats.svg' THEN
        RAISE 'tasks SVG template expected, got: %', ref;
      ELSE
        RAISE INFO 'OK: %', ref;
      END IF;
    END;

    BEGIN
      RAISE INFO 'find an unknown template';
      SELECT json_build_object('path', path) FROM find_template('html', '/unknown') INTO ref;
      IF ref->>'path' != 'null' THEN
        RAISE 'NULL expected, got: %', ref;
      ELSE
        RAISE INFO 'OK: %', ref;
      END IF;
    END;

    -- TEST CRUDL task routes
    BEGIN
      RAISE INFO 'POST 400 /task';
      SELECT * FROM post('/task', '{"subject": "to", "description": "do"}'::json) INTO res;
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
      SELECT * FROM post('/task', '{"subject": "todo", "description": "something"}'::json) INTO res;
      IF res.code != 201 OR res.data->>'subject' <> 'todo' OR res.data->>'state' <> 'done' THEN
        RAISE 'open task expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    -- remember task data
    ref := res.data;

    BEGIN
      RAISE INFO 'GET 200 /task';
      SELECT * FROM get('/task/'||(ref->>'id')) INTO res;
      IF res.code != 200 OR (res.data->>'id') <> (ref->>'id') THEN
        RAISE 'task details found expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'PUT 404 /task';
      SELECT * FROM put('/task/'||nextval('task_id_seq'), '{"subject":0}'::json) INTO res;
      IF res.code != 404 THEN
        RAISE 'not found expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'PUT 200 /task';
      SELECT * FROM put('/task/'||(ref->>'id'), '{"subject": "todo", "description": "something else"}'::json) INTO res;
      IF res.code = 200 AND (res.data->'task'->>'description') = 'something else' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'updated task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish') INTO res;
      IF res.code != 200 OR res.data->>'status' <> 'done' THEN
        RAISE 'finished task expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 405 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish') INTO res;
      IF res.code != 405 THEN
        RAISE 'method not allowed, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 405 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel') INTO res;
      IF res.code != 405 THEN
        RAISE 'method not allowed, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 404 /task/{id}/reopen';
      SELECT * FROM post('/task/'||nextval('task_id_seq')||'/reopen') INTO res;
      IF res.code != 404 THEN
        RAISE 'not found expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK:  % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/reopen';
      SELECT * FROM post('/task/'||(ref->>'id')||'/reopen') INTO res;
      IF res.code != 200 OR res.data->>'status' <> 'open' THEN
        RAISE 'reopened task expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'POST 200 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel') INTO res;
      IF res.code != 200 OR res.data->>'status' <> 'cancelled' THEN
        RAISE 'cancelled task expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks';
      SELECT * FROM get('/tasks') INTO res;
      IF res.code != 200 OR json_array_length(res.data->'tasks') != 2 THEN
        RAISE 'task list expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO '% %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks?status=open';
      SELECT * FROM get('/tasks?status=open') INTO res;
      IF res.code != 200 OR json_array_length(res.data->'tasks') != 1 THEN
        RAISE 'open task list expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO '% %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /tasks?status=done';
      SELECT * FROM get('/tasks?status=done') INTO res;
      IF res.code != 200 OR json_array_length(res.data->'tasks') != 0 THEN
        RAISE 'empty open task list expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO '% %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'DELETE 204 /task';
      SELECT * FROM delete('/task/'||(ref->>'id')) INTO res;
      IF res.code != 204 THEN
        RAISE 'no content expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    -- TEST CRUDL contact routes
    BEGIN
      RAISE INFO 'POST 400 /contact';
      SELECT * FROM
      post('/contact', '{"name": "cname", "street": "astreet", "zip": "invalid", "city": "acity"}'::json)
      INTO res;
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
      SELECT *
      FROM post('/contact', '{"name": "cname", "street": "astreet", "zip": 12345, "city": "acity"}'::json)
      INTO res;
      IF res.code != 201 OR res.data->>'name' <> 'cname' THEN
        RAISE 'contact record expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    -- reference the new contact
    ref := res.data;

    BEGIN
      RAISE INFO 'PUT 200 /contact/{id}';
      SELECT * FROM put('/contact/'||(ref->>'id'), '{"name": "cname", "comment": "some notes"}'::json) INTO res;
      IF res.code != 200 OR res.data->>'comment' <> 'some notes' THEN
        RAISE 'contact update expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /contact/{id}';
      SELECT * FROM get('/contact/'||(ref->>'id')) INTO res;
      IF res.code != 200 THEN
        RAISE 'contact expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    -- build an address update
    ref := json_build_object('street', 'nstreet', 'zip', '98765', 'city', 'ncity');

    BEGIN
      RAISE INFO 'PUT 200 /contact/{id}/address';
      SELECT * FROM put('/contact/'||(res.data->>'id')||'/address', ref) INTO res;
      IF res.code != 200 OR res.data->>'zip' <> '98765' THEN
        RAISE 'address update expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'GET 200 /contacts';
      SELECT * FROM get('/contacts') INTO res;
      IF res.code != 200 OR json_array_length(res.data) != 2 THEN
        RAISE 'contact list expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'DELETE 204 /contact';
      SELECT * FROM delete('/contact/'||(res.data->1->>'id')) INTO res;
      IF res.code != 204 THEN
        RAISE 'no content expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

    -- TEST dashboard
    BEGIN
      RAISE INFO 'GET 200 /';
      SELECT * FROM get('/') INTO res;
      IF res.code != 200 THEN
        RAISE 'dashboard content expected, got: % %', res.code, res.data;
      ELSE
        RAISE INFO 'OK: % %', res.code, res.data;
      END IF;
    END;

  RAISE INFO 'OK ;-)';
  END;
$$;
ROLLBACK;

