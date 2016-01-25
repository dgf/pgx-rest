-- contact management specification

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
      RAISE INFO 'SPEC: contact management';
      PERFORM create_contact('Danny Gräf', 'Auf der Wiese 17', '12372', 'Berlin');
    END;

    BEGIN
      RAISE INFO 'TEST: POST 400 /contact';
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
      RAISE INFO 'TEST: POST 201 /contact';
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
      RAISE INFO 'TEST: PUT 200 /contact/{id}';
      SELECT * FROM put('/contact/'||(ref->>'id'), '{"name": "cname", "comment": "some notes"}'::json) INTO res;
      IF res.code = 200 AND res.data->>'comment' = 'some notes' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact update expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /contact/{id}';
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
      RAISE INFO 'TEST: PUT 200 /contact/{id}/address';
      SELECT * FROM put('/contact/'||(res.data->>'id')||'/address', ref) INTO res;
      IF res.code = 200 AND res.data->>'zip' = '98765' THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'address update expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: GET 200 /contacts';
      SELECT * FROM get('/contacts') INTO res;
      IF res.code = 200 AND json_array_length(res.data) = 2 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'contact list expected, got: % %', res.code, res.data;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: DELETE 204 /contact';
      SELECT * FROM delete('/contact/'||(res.data->1->>'id')) INTO res;
      IF res.code = 204 THEN
        RAISE INFO 'OK: % %', res.code, res.data;
      ELSE
        RAISE 'no content expected, got: % %', res.code, res.data;
      END IF;
    END;
  END;
$$;
ROLLBACK;
