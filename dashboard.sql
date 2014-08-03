-- dashboard endpoint with open tasks and contact list

INSERT INTO route (method, path, proc, description) VALUES
('get', '/dashboard', 'get_dashboard', 'index page');

CREATE FUNCTION get_dashboard(req request)
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

