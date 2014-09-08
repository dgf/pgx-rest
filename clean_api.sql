-- cleanup in reverse order, this also documents the API top down

-- application endpoints
DROP FUNCTION IF EXISTS create_task_form(request);
DROP FUNCTION IF EXISTS delete_contact(request);
DROP FUNCTION IF EXISTS delete_task(request);
DROP FUNCTION IF EXISTS get_contact(request);
DROP FUNCTION IF EXISTS get_contacts(request);
DROP FUNCTION IF EXISTS get_dashboard(request);
DROP FUNCTION IF EXISTS get_task(request);
DROP FUNCTION IF EXISTS get_tasks(request);
DROP FUNCTION IF EXISTS post_contact(request);
DROP FUNCTION IF EXISTS post_task_cancel(request);
DROP FUNCTION IF EXISTS post_task_finish(request);
DROP FUNCTION IF EXISTS post_task_reopen(request);
DROP FUNCTION IF EXISTS post_task(request);
DROP FUNCTION IF EXISTS put_contact_address(request);
DROP FUNCTION IF EXISTS put_contact(request);
DROP FUNCTION IF EXISTS put_task(request);

-- routing endpoints
DROP FUNCTION IF EXISTS call(method, text, json);
DROP FUNCTION IF EXISTS delete(text);
DROP FUNCTION IF EXISTS get(text);
DROP FUNCTION IF EXISTS post(text);
DROP FUNCTION IF EXISTS post(text, json);
DROP FUNCTION IF EXISTS put(text, json);
DROP FUNCTION IF EXISTS find_template(text, text);
DROP FUNCTION IF EXISTS route_action(method, text, text[]);
DROP FUNCTION IF EXISTS route_action(method, text);
DROP TRIGGER  IF EXISTS route_path_match ON route;
DROP FUNCTION IF EXISTS route_path_match();
DROP TABLE    IF EXISTS template;
DROP TABLE    IF EXISTS route;
DROP TYPE     IF EXISTS error;
DROP TYPE     IF EXISTS method;
DROP TYPE     IF EXISTS response;
DROP TYPE     IF EXISTS request;

-- business logic
DROP FUNCTION IF EXISTS cancel_task(int);
DROP FUNCTION IF EXISTS create_contact(text, text, text, text);
DROP FUNCTION IF EXISTS create_task(text, text);
DROP FUNCTION IF EXISTS delete_contact(int);
DROP FUNCTION IF EXISTS delete_task(int);
DROP FUNCTION IF EXISTS finish_task(int);
DROP FUNCTION IF EXISTS json_build_task(task);
DROP FUNCTION IF EXISTS reopen_task(int);
DROP FUNCTION IF EXISTS update_contact_address(int, text, text, text);
DROP FUNCTION IF EXISTS update_contact(int, text, text);
DROP FUNCTION IF EXISTS update_task(int, text, text);
DROP TABLE    IF EXISTS task;
DROP TABLE    IF EXISTS contact;
DROP TABLE    IF EXISTS address;
DROP TYPE     IF EXISTS status;

