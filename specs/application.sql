-- example application specification

-- requires all module paths of rest.globals() call
SET search_path TO application, tasks, contacts, files, rest, public;

BEGIN TRANSACTION;
DO $$
  DECLARE -- references to work with
    ref json;          -- an JSON object
    sid uuid;          -- an user sesssion
    res http_response; -- a function result
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: application';
      PERFORM create_contact('Danny Gräf', 'Auf der Wiese 17', '12372', 'Berlin');
      PERFORM create_task('keep on going', 'live every day to its fullest');
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /';
      SELECT * FROM get('/') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'contacts') = 1 AND json_array_length(res.data->'tasks') = 1 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'homepage content expected, got: % %', res.code, res.data;
      END IF;
    END;
  END;
$$;
ROLLBACK;

