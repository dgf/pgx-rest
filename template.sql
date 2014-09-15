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

-- list all templates
INSERT INTO route (method, path, proc, description) VALUES
('get', '/templates', 'get_templates', 'list all published templates');
CREATE FUNCTION get_templates(req request)
  RETURNS response AS $$ DECLARE templates json;
  BEGIN
    WITH template_list AS (
      SELECT t.*, json_agg(json_build_object(
        'method', r.method
      , 'params', r.params
      , 'path', r.path)
      ORDER BY r.method, r.path) AS routes
      FROM template t
      JOIN route r ON r.proc = t.proc
      GROUP BY t.id
    )
    SELECT json_agg(json_build_object(
      'path', path
    , 'proc', proc
    , 'mime', mime
    , 'locals', locals
    , 'routes', routes)
    ORDER BY t.path, t.mime)
    FROM template_list t INTO templates;
    RETURN (200, json_build_object('templates', templates));
  END;
$$ LANGUAGE plpgsql;

INSERT INTO template (proc, mime, path, locals) VALUES
('get_routes'   , 'html', 'routes.html', '{"title":"Public routes API"}'::json),
('get_templates', 'html', 'templates.html', '{"title":"Published templates"}'::json);

