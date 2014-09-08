-- route templates

CREATE TABLE template (
  id     serial PRIMARY KEY,
  proc   text   NOT NULL, -- SQL function
  mime   text   NOT NULL, -- mime type
  path   text   NOT NULL, -- template file path
  locals json   NOT NULL  -- default template values like the title of a HTML template
);

-- template path lookup
CREATE FUNCTION find_template(r_mime text, r_path text, OUT path text, OUT locals json)
  AS $$ DECLARE r route; t template;
  BEGIN
    SELECT * FROM route WHERE 'get' = method AND r_path ~ match INTO STRICT r;
    SELECT * FROM template WHERE r_mime = mime AND r.proc = proc INTO STRICT t;
    path := t.path;
    locals := t.locals;
  EXCEPTION WHEN no_data_found THEN path := NULL;
  END;
$$ LANGUAGE plpgsql
   -- Export access for all!
   SECURITY DEFINER;

