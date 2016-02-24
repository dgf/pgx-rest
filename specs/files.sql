-- file management specification

-- requires all module paths of rest.globals() call
SET search_path TO application, tasks, contacts, files, rest, public;

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;         -- JSON object
    sid uuid;         -- user session
    res app_response; -- function result
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: file management';
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
      RAISE INFO 'TEST: POST 201 /upload';
      SELECT * FROM upload(sid, 'a.txt', 'text/plain', 'a file', 'text data') INTO res;
      IF res.code = 201 AND res.data->>'name' = 'a.txt' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'file details expected, got: % %', res.code, res.data;
      END IF;
    END;

    -- remember file meta data
    ref := res.data;

    BEGIN
      RAISE INFO 'TEST: GET 200 /file/{id}';
      SELECT * FROM get('/file/'||(ref->>'id'), sid) INTO res;
      IF res.code = 200 AND res.data->'file'->>'id' = ref->>'id' AND (res.session->>'id')::uuid = sid THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'file details expected, got: % % %', res.code, res.session, res.data;
      END IF;
    END;

  END;
$$;
ROLLBACK;

