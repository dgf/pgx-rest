-- file management
CREATE SCHEMA files;
SET search_path TO files, rest, public;

-- file routes
INSERT INTO route (method, path, proc, legitimate, description) VALUES
('delete', '/file/{id}'       , 'delete_file'     , '{"user"}' , 'delete a file'),
('get'   , '/file'            , 'form_upload'     , '{"user"}' , 'file upload form'),
('get'   , '/file/{id}/delete', 'form_delete_file', '{"user"}' , 'confirm file delete'),
('get'   , '/file/{id}'       , 'get_file'        , '{"every"}', 'file details page'),
('get'   , '/files'           , 'get_files'       , '{"every"}', 'file list'),
('put'   , '/file/{id}'       , 'put_file'        , '{"user"}' , 'update file meta data');

-- file templates
INSERT INTO template (proc, mime, path, locals) VALUES
('form_delete_file', 'html', 'files/delete.html' , '{"title":"Confirm file delete"}'::json),
('form_upload'     , 'html', 'files/upload.html' , '{"title":"File upload"}'::json),
('get_file'        , 'html', 'files/details.html', '{"title":"File details"}'::json),
('get_files'       , 'html', 'files/index.html'  , '{"title":"File list"}'::json);

-- file store
CREATE TABLE afile (
  id          serial  PRIMARY KEY,
  user_id     int     NOT NULL REFERENCES auser, -- owner
  name        text    NOT NULL, -- file name
  mime        text    NOT NULL, -- mime type
  description text    NOT NULL DEFAULT '',
  data        text    NOT NULL -- base64 encoded file content
);

-- serialize file meta data
CREATE FUNCTION json_build_file(f afile)
  RETURNS json AS $$ DECLARE ref text[] := ARRAY[f.id];
  BEGIN
    RETURN json_build_object(
      'id', f.id
    , 'name', f.name
    , 'mime', f.mime
    , 'description', f.description
    , 'routes', json_build_object(
        'delete', route_action('delete', 'delete_file', ref)
      , 'download', '/download/'||f.id
      , 'get', route_action('get', 'get_file', ref)
      , 'put', route_action('put', 'put_file', ref))
    );
  END;
$$ LANGUAGE plpgsql;

-- public form data upload
CREATE FUNCTION public.upload(c_session uuid, f_name text, f_mime text, f_description text, f_data text)
  RETURNS http_response AS $$
  DECLARE
    f afile; s asession; u auser;
    g json; rs json;
  BEGIN
    -- fetch globals and session
    SELECT * FROM globals() INTO STRICT g;
    SELECT * FROM refresh_session(c_session) INTO STRICT s;

    -- unauthenticated
    IF s IS NULL THEN
      RETURN (401, g, rs, to_json(('unauthenticated', 'authentication required')::error));

    -- authenticated
    ELSE
      -- serialize session and user info
      SELECT * FROM auser WHERE id = s.user_id INTO STRICT u;
      rs := json_build_session(s, u);

      -- create file
      INSERT INTO afile (user_id, name, mime, description, data)
      VALUES (u.id, f_name, f_mime, f_description, f_data)
      RETURNING * INTO STRICT f;
      RETURN (201, g, rs, json_build_file(f));
    END IF;
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, g, rs, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql
   -- Everybody can try an upload!
   SECURITY DEFINER;

-- public HTTP download file data
CREATE FUNCTION public.download(c_session uuid, f_id int)
  RETURNS http_response AS $$
  DECLARE
    f afile; s asession; u auser;
    g json; rs json;
  BEGIN
    -- fetch globals and session
    SELECT * FROM globals() INTO STRICT g;
    SELECT * FROM refresh_session(c_session) INTO STRICT s;

    -- unauthenticated
    IF s IS NULL THEN
      RETURN (401, g, rs, to_json(('unauthenticated', 'authentication required')::error));

    -- authenticated
    ELSE
      -- serialize session and user info
      SELECT * FROM auser WHERE id = s.user_id INTO STRICT u;
      rs := json_build_session(s, u);
 
      -- query file with data
      SELECT * FROM afile WHERE id = f_id INTO STRICT f;
      RETURN (200, g, rs, to_json(f));
    END IF;
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (404, g, rs, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql
   -- Everybody can try a download!
   SECURITY DEFINER;

-- REST file API

CREATE FUNCTION delete_file(req request)
  RETURNS response AS $$ DECLARE f afile;
  BEGIN
    DELETE FROM afile WHERE id::text = req.params->>'id';
    RETURN (204, json_build_object('routes', json_build_object('next', route_action('get', 'get_files'))));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_file(req request)
  RETURNS response AS $$ DECLARE f afile; u auser;
  BEGIN
    SELECT * FROM afile WHERE id::text = req.params->>'id' INTO STRICT f;
    SELECT * FROM auser WHERE id = f.user_id INTO STRICT u;
    RETURN (200, json_build_object(
      'file', json_build_file(f)
    , 'owner', u.login)
    );
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_files(req request)
  RETURNS response AS $$ DECLARE files json;
  BEGIN
    SELECT json_agg(json_build_file(f) ORDER BY f.name)
    FROM afile f INTO files;
    RETURN (200, json_build_object(
      'files', COALESCE(files, '[]'::json)
    , 'routes', json_build_object('upload', route_action('get', 'form_upload')))
    );
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION put_file(req request)
  RETURNS response AS $$ DECLARE f afile; u auser;
  BEGIN
    UPDATE afile SET name = req.body->>'name', description = req.body->>'description'
    WHERE id::text = req.params->>'id' RETURNING * INTO STRICT f;
    SELECT * FROM auser WHERE id = f.user_id INTO STRICT u;
    RETURN (200, json_build_object(
      'file', json_build_file(f)
    , 'owner', u.login
    , 'notice', json_build_object('level', 'info', 'message', 'file updated'))
    );
  END;
$$ LANGUAGE plpgsql;

-- HTML form task API

CREATE FUNCTION form_delete_file(req request)
  RETURNS response AS $$
  BEGIN
    RETURN get_file(req);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION form_upload(req request)
  RETURNS response AS $$
  BEGIN
    RETURN (200, json_build_object(
      'placeholder', json_build_object('name', 'file name', 'description', 'What is inside?')
    , 'routes', json_build_object('upload', '/upload'))
    );
  END;
$$ LANGUAGE plpgsql;

