-- task management example
CREATE SCHEMA tasks;
SET search_path TO tasks, rest, public;

-- define routes
INSERT INTO route (method, path, proc, legitimate, description) VALUES
('get'   , '/task'                 , 'form_post_task'       , '{"every"}', 'template route of task creation form'),
('get'   , '/tasks'                , 'get_tasks'            , '{"every"}', 'all tasks'),
('get'   , '/tasks?status={status}', 'get_tasks'            , '{"every"}', 'filter tasks'),
('get'   , '/task/{id}'            , 'get_task'             , '{"every"}', 'get task details'),
('post'  , '/task'                 , 'post_task'            , '{"every"}', 'create a task'),
('delete', '/task/{id}'            , 'delete_task'          , '{"user"}' , 'delete a task'),
('get'   , '/task/{id}/cancel'     , 'form_post_task_cancel', '{"user"}' , 'confirm task cancel'),
('get'   , '/task/{id}/delete'     , 'form_delete_task'     , '{"user"}', 'confirm task delete'),
('get'   , '/task/{id}/finish'     , 'form_post_task_finish', '{"user"}' , 'confirm task finish'),
('get'   , '/task/{id}/reopen'     , 'form_post_task_reopen', '{"user"}' , 'confirm task reopen'),
('post'  , '/task/{id}/cancel'     , 'post_task_cancel'     , '{"user"}' , 'cancel a task'),
('post'  , '/task/{id}/finish'     , 'post_task_finish'     , '{"user"}' , 'finish a task'),
('post'  , '/task/{id}/reopen'     , 'post_task_reopen'     , '{"user"}' , 'reopen a task'),
('put'   , '/task/{id}'            , 'put_task'             , '{"user"}' , 'update a task');

-- map templates
INSERT INTO template (proc, mime, path, locals) VALUES
('get_task'             , 'html', 'tasks/details.html', '{"title":"Task details"}'::json),
('get_tasks'            , 'html', 'tasks/index.html'  , '{"title":"Task list"}'::json),
('get_tasks'            , 'svg' , 'tasks/stats.svg'   , '{"title":"Task statistics"}'::json),
('form_delete_task'     , 'html', 'tasks/delete.html' , '{"title":"Confirm task delete"}'::json),
('form_post_task'       , 'html', 'tasks/create.html' , '{"title":"Create a task"}'::json),
('form_post_task_cancel', 'html', 'tasks/cancel.html' , '{"title":"Cancel task"}'::json),
('form_post_task_finish', 'html', 'tasks/finish.html' , '{"title":"Finish task"}'::json),
('form_post_task_reopen', 'html', 'tasks/reopen.html' , '{"title":"Reopen task"}'::json);

-- status of a task
CREATE TYPE status AS ENUM ('open', 'cancelled', 'done');

-- task definition
CREATE TABLE task (
  id          serial PRIMARY KEY,
  status      status NOT NULL DEFAULT 'open',
  subject     text   NOT NULL, CHECK (length(subject) > 2 AND length(subject) < 57),
  description text   NOT NULL DEFAULT ''
);

-- serialize task record with route actions
CREATE FUNCTION json_build_task(t task)
  RETURNS json AS $$ DECLARE ref text[] := ARRAY[t.id]; routes text[];
  BEGIN
    routes := ARRAY[
      'get', route_action('get', 'get_task', ref)
    , 'delete', route_action('delete', 'delete_task', ref)
    , 'put', route_action('put', 'put_task', ref)
    ];
    IF t.status <> 'open' THEN
      routes := array_cat(routes, ARRAY[
        'reopen', route_action('post', 'post_task_reopen', ref)
      ]);
    ELSE
      routes := array_cat(routes, ARRAY[
        'cancel', route_action('post', 'post_task_cancel', ref)
      , 'finish', route_action('post', 'post_task_finish', ref)
      ]);
    END IF;
    RETURN json_build_object(
      'id', t.id
    , 'status', t.status
    , 'subject' , t.subject
    , 'description' , t.description
    , 'routes', json_object(routes)
    );
  END;
$$ LANGUAGE plpgsql;

-- SQL task API

CREATE FUNCTION cancel_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    UPDATE task SET status = 'cancelled'
    WHERE id = t_id AND status = 'open'
    RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION create_task(t_subject text, t_description text)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    INSERT INTO task (subject, description) VALUES (t_subject, t_description) RETURNING * INTO t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    DELETE FROM task WHERE id = t_id RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_open_tasks()
  RETURNS int AS $$ DECLARE c int;
  BEGIN
    SELECT count(*) FROM task WHERE status = 'open' INTO c;
    RETURN c;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION finish_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    UPDATE task SET status = 'done'
    WHERE id = t_id AND status = 'open'
    RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION reopen_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    UPDATE task SET status = 'open'
    WHERE id = t_id
    RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION update_task(t_id int, t_subject text, t_description text)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    UPDATE task SET subject = t_subject, description = t_description
    WHERE id = t_id RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

-- REST task API

CREATE FUNCTION delete_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := delete_task((req.params->>'id')::int);
    RETURN (204, json_build_object('routes', json_build_object('next', route_action('get', 'get_tasks'))));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    SELECT * FROM task WHERE id = (req.params->>'id')::int INTO STRICT t;
    RETURN (200, json_build_object(
      'task', json_build_task(t)
    , 'routes', json_build_object('list', route_action('get', 'get_tasks')))
    );
   END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION get_tasks(req request)
  RETURNS response AS $$ DECLARE l json;
  BEGIN
    IF (req.params->>'status') IS NULL THEN
      SELECT json_agg(json_build_task(t) ORDER BY t.status, t.subject) FROM task t INTO l;
    ELSE
      SELECT json_agg(json_build_task(t) ORDER BY t.subject) FROM task t WHERE t.status = (req.params->>'status')::status INTO l;
    END IF;
    RETURN (200, json_build_object(
      'tasks', COALESCE(l, '[]'::json)
    , 'routes', json_build_object('post', route_action('post', 'post_task')))
    );
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task(req request)
  RETURNS response AS $$ DECLARE t task; j json;
  BEGIN
    t := create_task(req.body->>'subject', req.body->>'description');
    j := json_build_task(t);
    RETURN (201, j);
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task_cancel(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := cancel_task((req.params->>'id')::int);
    RETURN (200, json_build_task(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (405, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task_finish(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := finish_task((req.params->>'id')::int);
    RETURN (200, json_build_task(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (405, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task_reopen(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := reopen_task((req.params->>'id')::int);
    RETURN (200, json_build_task(t));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION put_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := update_task((req.params->>'id')::int, req.body->>'subject', req.body->>'description');
    RETURN (200, json_build_object(
      'task', json_build_task(t)
    , 'notice', json_build_object('level', 'info', 'message', 'task updated')
    , 'routes', json_build_object('list', route_action('get', 'get_tasks')))
    );
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

-- HTML form task API

CREATE FUNCTION form_post_task(req request)
  RETURNS response AS $$
  BEGIN
    RETURN (200, json_build_object(
      'placeholder', json_build_object('subject', 'What?', 'description', 'Why How for Whom?')
    , 'routes', json_build_object(
        'list', route_action('get', 'get_tasks')
      , 'post', route_action('post', 'post_task')))
    );
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION form_delete_task(req request)
  RETURNS response AS $$
  BEGIN
    RETURN get_task(req);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION form_post_task_cancel(req request)
  RETURNS response AS $$
  BEGIN
    RETURN get_task(req);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION form_post_task_finish(req request)
  RETURNS response AS $$
  BEGIN
    RETURN get_task(req);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION form_post_task_reopen(req request)
  RETURNS response AS $$
  BEGIN
    RETURN get_task(req);
  END;
$$ LANGUAGE plpgsql;

