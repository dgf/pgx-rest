-- application endpoint with open tasks and contact list
CREATE SCHEMA application;
SET search_path TO application, tasks, contacts, files, rest, public;

-- predefine application settings
INSERT INTO app_settings (schema, name, globals) VALUES
('application', 'Example Application', 'get_configuration');

INSERT INTO route (method, path, schema, proc, description) VALUES
('get', '/', 'application', 'homepage', 'index page');

-- public index route
CREATE FUNCTION homepage(req request)
  RETURNS response AS $$ DECLARE tasks json; contacts json;
  BEGIN

    -- open tasks
    SELECT json_agg(json_build_object('id', t.id, 'subject', t.subject))
    FROM task t WHERE status = 'open' INTO tasks;

    -- contact list
    SELECT json_agg(json_build_object('id', c.id, 'name', c.name, 'address', concat_ws(' ', a.street, a.zip, a.city)))
    FROM contact c JOIN address a ON c.address_id = a.id INTO contacts;

    RETURN (200, json_build_object('contacts', contacts, 'tasks', tasks));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (205, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

-- create globals
CREATE FUNCTION get_configuration()
  RETURNS json AS $$ DECLARE s app_settings;
  BEGIN
    SELECT * FROM app_settings INTO STRICT s;
    RETURN json_build_object(
      'app_name', s.name
    , 'open_tasks', get_open_tasks()
    , 'routes', json_build_object(
        'index', route_action('get', 'homepage')
      , 'contacts', route_action('get', 'get_contacts')
      , 'files', route_action('get', 'get_files')
      , 'tasks', route_action('get', 'get_tasks'))
    );
  END;
$$ LANGUAGE plpgsql;

-- create default users
SELECT add_user('icke', 'secret', 'an admin', '{"admin","user"}');
SELECT add_user('er', 'secret', 'an user', '{"user"}');
