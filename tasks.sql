-- task management example

INSERT INTO route (method, path, proc, description) VALUES
('delete' , '/task/{id}'             , 'delete_task'      , 'delete a task'),
('get'    , '/tasks'                 , 'get_tasks'        , 'all tasks'),
('get'    , '/tasks?status={status}' , 'get_tasks'        , 'filter tasks'),
('post'   , '/task/{id}/cancel'      , 'post_task_cancel' , 'cancel a task'),
('post'   , '/task/{id}/finish'      , 'post_task_finish' , 'finish a task'),
('post'   , '/task/{id}/reopen'      , 'post_task_reopen' , 'reopen a task'),
('post'   , '/task'                  , 'post_task'        , 'create a task'),
('put'    , '/task/{id}'             , 'put_task'         , 'update a task');

CREATE TYPE status AS ENUM ('open', 'cancelled', 'done');

CREATE TABLE task (
  id          serial PRIMARY KEY,
  status      status NOT NULL DEFAULT 'open',
  subject     text   NOT NULL, CHECK (length(subject) > 2 AND length(subject) < 57),
  description text   NOT NULL DEFAULT ''
);

CREATE FUNCTION get_tasks(req request)
  RETURNS response AS $$ DECLARE l json;
  BEGIN
    IF (req.params->>'status') IS NULL THEN
      SELECT json_agg(t) FROM task t INTO l;
    ELSE
      SELECT json_agg(t) FROM task t WHERE t.status = (req.params->>'status')::status INTO l;
    END IF;
    RETURN (CASE WHEN l IS NULL THEN 205 ELSE 200 END, l);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION create_task(t_subject text, t_description text)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    INSERT INTO task (subject, description) VALUES (t_subject, t_description) RETURNING * INTO t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := create_task(req.body->>'subject', req.body->>'description');
    RETURN (201, to_json(t));
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
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

CREATE FUNCTION put_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := update_task((req.params->>'id')::int, req.body->>'subject', req.body->>'description');
    RETURN (200, to_json(t));
  EXCEPTION
    WHEN integrity_constraint_violation THEN
      RETURN (400, to_json((SQLSTATE, SQLERRM)::error));
    WHEN no_data_found THEN
      RETURN (404, to_json((SQLSTATE, SQLERRM)::error));
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

CREATE FUNCTION post_task_finish(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := finish_task((req.params->>'id')::int);
    RETURN (200, to_json(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (405, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION cancel_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    UPDATE task SET status = 'cancelled'
    WHERE id = t_id AND status = 'open'
    RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION post_task_cancel(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := cancel_task((req.params->>'id')::int);
    RETURN (200, to_json(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (405, to_json((SQLSTATE, SQLERRM)::error));
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

CREATE FUNCTION post_task_reopen(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := reopen_task((req.params->>'id')::int);
    RETURN (200, to_json(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (404, to_json((SQLSTATE, SQLERRM)::error));
   END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete_task(t_id int)
  RETURNS task AS $$ DECLARE t task;
  BEGIN
    DELETE FROM task WHERE id = t_id RETURNING * INTO STRICT t;
    RETURN t;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION delete_task(req request)
  RETURNS response AS $$ DECLARE t task;
  BEGIN
    t := delete_task((req.params->>'id')::int);
    RETURN (204, to_json(t));
  EXCEPTION
    WHEN no_data_found THEN
      RETURN (404, to_json((SQLSTATE, SQLERRM)::error));
  END;
$$ LANGUAGE plpgsql;

