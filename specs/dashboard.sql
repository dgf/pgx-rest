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
      RAISE INFO 'SPEC: dashboard';
      PERFORM create_contact('Danny Gräf', 'Auf der Wiese 17', '12372', 'Berlin');
      PERFORM create_task('keep on going', 'live every day to its fullest');
      PERFORM add_user('er', 'secret', 'test user', '{"user"}');
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /';
      SELECT * FROM get('/') INTO res;
      IF res.code = 200 AND json_array_length(res.data->'contacts') = 1 AND json_array_length(res.data->'tasks') = 1 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'dashboard content expected, got: % %', res.code, res.data;
      END IF;
    END;
  END;
$$;
ROLLBACK;

