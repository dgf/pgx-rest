-- contact management example

INSERT INTO route (method, path, proc, description) VALUES
('delete' , '/contact/{id}'          , 'delete_contact'      , 'delete a contact'),
('get'    , '/contact/{id}'          , 'get_contact'         , 'contact details'),
('get'    , '/contacts'              , 'get_contacts'        , 'contact list'),
('post'   , '/contact'               , 'post_contact'        , 'create a contact'),
('put'    , '/contact/{id}/address'  , 'put_contact_address' , 'update contact address'),
('put'    , '/contact/{id}'          , 'put_contact'         , 'update contact details');

CREATE TABLE address (
  id          serial PRIMARY KEY,
  zip         text   NOT NULL, CHECK (zip ~ '^\d{5}$'),
  city        text   NOT NULL, CHECK (length(city) > 3 AND length(city) < 37),
  street      text   NOT NULL, CHECK (length(street) > 3 AND length(street) < 57)
);

CREATE TABLE contact (
  id          serial PRIMARY KEY,
  address_id  int    NOT NULL REFERENCES address,
  name        text   NOT NULL UNIQUE,
  comment     text   NOT NULL DEFAULT ''
);

CREATE FUNCTION get_contacts(req request)
  RETURNS response AS $$ DECLARE l json;
  BEGIN
    SELECT json_agg(c) FROM contact c INTO l;
    RETURN (CASE WHEN l IS NULL THEN 205 ELSE 200 END, l);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_contact(req request)
  RETURNS response AS $$ DECLARE r record;
  BEGIN
    SELECT c.id, c.name, c.comment, concat_ws(' ', a.street, a.zip, a.city) AS address
    FROM contact c JOIN address a ON c.address_id = a.id
    WHERE c.id = (req.params->>'id')::int INTO STRICT r;
    RETURN (200, to_json(r));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION create_contact(c_name text, a_street text, a_zip text, a_city text)
  RETURNS contact AS $$ DECLARE a address; c contact;
  BEGIN
    INSERT INTO address (street, zip, city)
    VALUES (a_street, a_zip, a_city)
    RETURNING * INTO a;
    INSERT INTO contact (name, address_id)
    VALUES (c_name, a.id)
    RETURNING * INTO c;
    RETURN c;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_contact(req request)
  RETURNS response AS $$ DECLARE c contact;
  BEGIN
    c := create_contact(req.body->>'name', req.body->>'street', req.body->>'zip', req.body->>'city');
    RETURN (201, to_json(c));
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_contact(c_id int, c_name text, c_comment text)
  RETURNS contact AS $$ DECLARE c contact;
  BEGIN
    UPDATE contact SET name = c_name, comment = c_comment
    WHERE id = c_id RETURNING * INTO STRICT c;
    RETURN c;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION put_contact(req request)
  RETURNS response AS $$ DECLARE c contact;
  BEGIN
    c := update_contact((req.params->>'id')::int, req.body->>'name', req.body->>'comment');
    RETURN (200, to_json(c));
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_contact_address(c_id int, a_street text, a_zip text, a_city text)
  RETURNS address AS $$ DECLARE a address;
  BEGIN
    UPDATE address SET street = a_street, zip = a_zip, city = a_city
    FROM contact WHERE contact.id = c_id AND contact.address_id = address.id RETURNING * INTO STRICT a;
    RETURN a;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION put_contact_address(req request)
  RETURNS response AS $$ DECLARE a address;
  BEGIN
    a := update_contact_address((req.params->>'id')::int, req.body->>'street', req.body->>'zip', req.body->>'city');
    RETURN (200, to_json(a));
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete_contact(c_id int)
  RETURNS contact AS $$ DECLARE c contact;
  BEGIN
    SELECT * FROM contact WHERE id = c_id INTO STRICT c;
    DELETE FROM contact WHERE id = c_id;
    DELETE FROM address WHERE id = c.address_id;
    RETURN c;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete_contact(req request)
  RETURNS response AS $$ DECLARE c contact;
  BEGIN
    c := delete_contact((req.params->>'id')::int);
    RETURN (204, to_json(c));
  END;
$$ LANGUAGE plpgsql;

