-- application endpoint with open tasks and contact list
CREATE SCHEMA application;
SET search_path TO application, tasks, contacts, rest, public;

-- predefine application settings
INSERT INTO asetting (app_name, globals) VALUES
('pgx-rest', 'get_configuration');

INSERT INTO route (method, path, proc, description) VALUES
('get', '/', 'homepage', 'index page');

-- public index route
CREATE FUNCTION homepage(req request)
  RETURNS response AS $$ DECLARE tasks json; contacts json;
  BEGIN
    SELECT json_agg(json_build_object('id', t.id, 'subject', t.subject))
    FROM task t WHERE status = 'open' INTO tasks;
    SELECT json_agg(json_build_object('id', c.id, 'name', c.name, 'address', concat_ws(' ', a.street, a.zip, a.city)))
    FROM contact c JOIN address a ON c.address_id = a.id INTO contacts;
    RETURN (200, json_build_object('contacts', contacts, 'tasks', tasks));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (205, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

-- create globals
CREATE FUNCTION get_configuration(s asetting)
  RETURNS json AS $$
  BEGIN
    RETURN json_build_object(
      'app_name', s.app_name
    , 'open_tasks', get_open_tasks()
    , 'routes', json_build_object(
        'index', route_action('get', 'homepage')
      , 'tasks', route_action('get', 'get_tasks')
      , 'contacts', route_action('get', 'get_contacts'))
    );
  END;
$$ LANGUAGE plpgsql;

-- create default users
SELECT add_user('icke', 'secret', 'an admin', '{"admin","user"}');
SELECT add_user('er', 'secret', 'an user', '{"user"}');

