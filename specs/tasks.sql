-- task management specification

-- requires all module paths of globals() call
SET search_path TO application, tasks, contacts, rest, public;

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;          -- an JSON object
    sid uuid;          -- an user sesssion
    res http_response; -- a function result
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: task management';
      PERFORM create_task('keep on going', 'live every day to its fullest');
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /postlogin as user';
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
      RAISE INFO 'TEST: POST 400 /task';
      SELECT * FROM post('/task', sid, '{"subject": "to", "description": "do"}'::json) INTO res;
      IF res.code = 400 AND res.data->>'message' ~ 'task_subject_check' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'bad request expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 201 /task';
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
      RAISE INFO 'TEST: GET 200 /task/{id}';
      SELECT * FROM get('/task/'||(ref->>'id'), sid) INTO res;
      IF res.code = 200 AND res.data->'task'->>'id' = ref->>'id' AND (res.session->>'id')::uuid = sid THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'task details expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: PUT 404 /task';
      SELECT * FROM put('/task/'||nextval('task_id_seq'), sid, '{"subject":123}'::json) INTO res;
      IF res.code = 404
        AND (res.session->>'id')::uuid = sid
        AND json_typeof(res.globals) = 'object' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'not found expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: PUT 200 /task';
      SELECT * FROM put('/task/'||(ref->>'id'), sid, '{"subject": "todo", "description": "something else"}'::json) INTO res;
      IF res.code = 200 AND (res.data->'task'->>'description') = 'something else' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'updated task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'done' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'finished task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 405 /task/{id}/finish';
      SELECT * FROM post('/task/'||(ref->>'id')||'/finish', sid) INTO res;
      IF res.code = 405 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'method not allowed, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 405 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel', sid) INTO res;
      IF res.code = 405 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'method not allowed, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 404 /task/{id}/reopen';
      SELECT * FROM post('/task/'||nextval('task_id_seq')||'/reopen', sid) INTO res;
      IF res.code = 404 THEN
        RAISE INFO 'OK:  % %', res.code, res.data;
      ELSE
        RAISE 'not found expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /task/{id}/reopen';
      SELECT * FROM post('/task/'||(ref->>'id')||'/reopen', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'open' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'reopened task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: POST 200 /task/{id}/cancel';
      SELECT * FROM post('/task/'||(ref->>'id')||'/cancel', sid) INTO res;
      IF res.code = 200 AND res.data->>'status' = 'cancelled' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'cancelled task expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /tasks';
      SELECT * FROM get('/tasks') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 2 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /tasks?status=open';
      SELECT * FROM get('/tasks?status=open') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 1 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'open task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /tasks?status=done';
      SELECT * FROM get('/tasks?status=done') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'tasks') = 0 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'empty open task list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: DELETE 204 /task';
      SELECT * FROM delete('/task/'||(ref->>'id'), sid) INTO res;
      IF res.code = 204 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'no content expected, got: % %', res.code, res.data;
      END IF;
    END;
  END;
$$;
ROLLBACK;

