# REST on PostgreSQL

Test implementation of REST compatible endpoints with PostgreSQL functions.

To start a ROCA based application, with a backend like this, you only need an
environment with a HTTP server and a PostgreSQL interface - that's it!

Requirements: only PostgreSQL 9.4 or higher

## Installation

To install [PostgreSQL][postgres] on Ubuntu or Debian follow these [instructions][pg_apt]
and use a tagged repository to overrule the libpg version.

    deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main 9.4

## Setup

Define a database name in the Makefile or use `rest_check` (the default).

create a fresh database and load required contrib modules
```sh
$ make init
$ make pg-setup
```

create example application
```sh
$ make application
```

list all existing targets
```sh
$ make
targets:                # list all targets
init:                   # create database
cli:                    # connect Postgres terminal
ng-download:            # fetch and unpack Nginx
ng-compile: ng-download # compile Nginx
ng-install: ng-compile  # install Nginx
ng-run:                 # start Nginx
pg-setup:               # setup Postgres extensions
clean:                  # clean database
rest: clean             # install REST schema
test: application       # run specifications
```

## Usage

The example application contains a rudimentary task and contact management.

list all existing routes
```SQL
SELECT method, path, proc, legitimate, description FROM route ORDER by path, method;
 method |          path          |         proc          | legitimate |             description              
--------+------------------------+-----------------------+------------+--------------------------------------
 get    | /                      | homepage              | {every}    | index page
 post   | /contact               | post_contact          | {every}    | create a contact
 get    | /contact/{id}          | get_contact           | {every}    | contact details
 put    | /contact/{id}          | put_contact           | {every}    | update contact details
 delete | /contact/{id}          | delete_contact        | {every}    | delete a contact
 put    | /contact/{id}/address  | put_contact_address   | {every}    | update contact address
 get    | /contacts              | get_contacts          | {every}    | contact list
 get    | /file                  | form_upload           | {every}    | file upload form
 get    | /file/{id}             | get_file              | {every}    | file details page
 put    | /file/{id}             | put_file              | {every}    | update file meta data
 delete | /file/{id}             | delete_file           | {every}    | delete a file
 get    | /file/{id}/delete      | form_delete_file      | {every}    | confirm file delete
 get    | /files                 | get_files             | {every}    | file list
 get    | /login                 | form_login            | {every}    | login form
 get    | /routes                | get_routes            | {admin}    | list all published routes
 get    | /task                  | form_post_task        | {every}    | template route of task creation form
 post   | /task                  | post_task             | {every}    | create a task
 get    | /task/{id}             | get_task              | {every}    | get task details
 put    | /task/{id}             | put_task              | {user}     | update a task
 delete | /task/{id}             | delete_task           | {user}     | delete a task
 get    | /task/{id}/cancel      | form_post_task_cancel | {user}     | confirm task cancel
 post   | /task/{id}/cancel      | post_task_cancel      | {user}     | cancel a task
 get    | /task/{id}/delete      | form_delete_task      | {user}     | confirm task delete
 get    | /task/{id}/finish      | form_post_task_finish | {user}     | confirm task finish
 post   | /task/{id}/finish      | post_task_finish      | {user}     | finish a task
 get    | /task/{id}/reopen      | form_post_task_reopen | {user}     | confirm task reopen
 post   | /task/{id}/reopen      | post_task_reopen      | {user}     | reopen a task
 get    | /tasks                 | get_tasks             | {every}    | all tasks
 get    | /tasks?status={status} | get_tasks             | {every}    | filter tasks
 get    | /templates             | get_templates         | {admin}    | list all published templates
```

create a new task
```SQL
SELECT data FROM post('/task', '{"subject": "todo", "description": "something"}'::json);
{"id" : 6, "status" : "open", "subject" : "todo", "description" : "something", "routes" : {"get" : "/task/6", "delete" : "/task/6", "put" : "/task/6", "cancel" : "/task/6/cancel", "finish" : "/task/6/finish"}}
(1 row)
```

## Public API routes

 * generic route execution: ```SELECT * FROM call('get', '/tasks', NULL, NULL);```
 * template resolver: ```SELECT * FROM find_template('html', '/tasks');```
 * HTTP basic login: ```SELECT * FROM login('icke', encode(concat_ws(':', u_login, u_password)::bytea, 'base64'));```
 * HTML form POST login: ```SELECT * FROM post_login('icke', 'secret');```
 * HTTP logout POST route: ```SELECT * FROM post_logout(sid);```

### Public file module access

 * HTML form POST upload: ```SELECT * FROM upload(sid, 'a.txt', 'text/plain', 'a file', 'text data')```
 * HTTP download GET route: ```SELECT * FROM download(sid, 1)```

## Development

define a schema and insert some entities
```SQL
CREATE TABLE entity (
  id   serial PRIMARY KEY,
  name text   NOT NULL
);
INSERT INTO entity (name)
VALUES ('first entity'), ('another one');
```

create JSON endpoint function
```SQL
CREATE FUNCTION get_entities(req request)
  RETURNS response AS $$ DECLARE l json;
  BEGIN
    SELECT json_agg(e) FROM entity e INTO l;
    RETURN (200, l);
  END;
$$ LANGUAGE plpgsql;
```

route the endpoint
```SQL
INSERT INTO route (method, path, proc, legitimate, description)
VALUES ('get', '/entities', 'get_entities', '{"every"}', 'entity list');
```

test the route
```SQL
SELECT * FROM get('/entities');
 code |               data                
------+-----------------------------------
  200 | [{"id":1,"name":"first entity"}, +
      |  {"id":2,"name":"another one"}]
```

## HTTP endpoints with OpenResty

Download, build and install an [OpenResty][openresty] release.
```sh
$ make ng-install
```

create an application user with login
```SQL
CREATE USER application WITH NOINHERIT ENCRYPTED PASSWORD 'SecreT';
ALTER USER application SET search_path = application, contacts, tasks, files, rest, public;
```

adjust credentials in `nginx.conf`
```sh
$ grep postgres_server nginx.conf
    postgres_server 127.0.0.1 dbname=rest_check user=application password=SecreT;
```

start Nginx
```sh
$ make ng-run
``` 

a simple task flow example session
```sh
# create a task
$ curl -D - -H "Content-Type: application/json" -d '{"subject":"todo", "description":"something"}' http://localhost:8080/task
HTTP/1.1 201 Created
Server: openresty/1.7.2.1
Date: Mon, 06 Oct 2014 20:40:04 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Set-Cookie: session=NULL; Path=/; Expires=Mon, 06-Oct-14 20:40:04 GMT

{"id" : 1, "status" : "open", "subject" : "todo", "description" : "something", "routes" : {"get" : "/task/1", "delete" : "/task/1", "put" : "/task/1", "cancel" : "/task/1/cancel", "finish" : "/task/1/finish"}}%

# list all open tasks
$ curl -D - http://localhost:8080/tasks\?status\=open
HTTP/1.1 200 OK
Server: openresty/1.7.2.1
Date: Mon, 06 Oct 2014 20:40:41 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Set-Cookie: session=NULL; Path=/; Expires=Mon, 06-Oct-14 20:40:41 GMT

{"tasks" : [{"id" : 1, "status" : "open", "subject" : "todo", "description" : "something", "routes" : {"get" : "/task/1", "delete" : "/task/1", "put" : "/task/1", "cancel" : "/task/1/cancel", "finish" : "/task/1/finish"}}], "routes" : {"post" : "/task"}}%

# finish the task (authenticated)
$ curl -u er -D - -X POST http://localhost:8080/task/1/finish
Enter host password for user 'er':
HTTP/1.1 200 OK
Server: openresty/1.7.2.1
Date: Mon, 06 Oct 2014 20:41:43 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Set-Cookie: session=4d2b96d8-2e53-42f6-a977-273fc42aa4fd; Path=/; Expires=Mon, 06-Oct-14 23:18:43 GMT

{"id" : 1, "status" : "done", "subject" : "todo", "description" : "something", "routes" : {"get" : "/task/1", "delete" : "/task/1", "put" : "/task/1", "reopen" : "/task/1/reopen"}}%

# there are no open tasks
$ curl -D - http://localhost:8080/tasks\?status\=open
HTTP/1.1 200 OK
Server: openresty/1.7.2.1
Date: Mon, 06 Oct 2014 20:42:27 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Set-Cookie: session=NULL; Path=/; Expires=Mon, 06-Oct-14 20:42:27 GMT

{"tasks" : [], "routes" : {"post" : "/task"}}%

# POST a x-www-form-urlencoded task
$ curl -D - -d 'subject=todo2&description=something2' http://localhost:8080/task
HTTP/1.1 201 Created
Server: openresty/1.7.2.1
Date: Mon, 06 Oct 2014 20:42:47 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Set-Cookie: session=NULL; Path=/; Expires=Mon, 06-Oct-14 20:42:47 GMT

{"id" : 2, "status" : "open", "subject" : "todo2", "description" : "something2", "routes" : {"get" : "/task/2", "delete" : "/task/2", "put" : "/task/2", "cancel" : "/task/2/cancel", "finish" : "/task/2/finish"}}%
```

### Authentication

Supports HTTP basic auth and HTML form based authentication.

#### HTTP Basic Auth

The way to communicate with a HTTP command client or library.

Flow:
 1. call of a restricted route, returns 401
 2. call it again with HTTP Basic Auth, results in:
   * 200 with route response and session cookie (logged in)
   * 400 invalid login call
   * 403 forbidden (not legitimated)
 3. reuse session cookie for additional requests (don't reauthenticate every request)
 4. post a /logout with cookie to invalidate the session

#### HTML Form Auth

Typical Browser interaction uses a form based dialog to prevent the hassle of
invalidating a HTTP basis auth session without JavaScript XHR.

Flow:
 1. call of a restricted route, returns 401
 2. get /login page and post /authenticate, returns
   * 200 JSON notice and session cookie (logged in)
   * 303 HTTP redirect back and session cookie (logged in)
   * 400 invalid login call
   * 403 forbidden (not legitimated)
 3. Browser reuses session cookie for additional requests
 4. post a /logout to invalidate the session

### Authorization

route execution is restricted with a legitimated set of roles

roles type with special entry "every" for public resource access

### Templates

requires [lua-resty-template][lua-resty-template], the simplest way to install it is `luarocks`
```sh
$ sudo luarocks install lua-resty-template
```

list all template mappings
```SQL
SELECT proc, mime, path, locals FROM template;
       proc       | mime |        path        |          locals
------------------+------+--------------------+---------------------------
 get_task         | html | tasks/details.html | {"title":"task details"}
 get_tasks        | html | tasks/index.html   | {"title":"task list"}
 get_tasks        | svg  | tasks/stats.svg    | {"title":"task stats"}
 create_task_form | html | tasks/create.html  | {"title":"create a task"}
(4 rows)
```

### Architecture

internal route proccessing

 1. NG get cookie session ID
 2. NG login with HTTP basic auth > PG login()
 3. PG update session
 4. PG authorized call
 5. NG handle response (render template)


### HTML HTTP REST Hacks for ROCA

The lack of HTTP methods in HTML should have no effects on the REST interface.
To minify the impact on the business layer there some default behaviours implemented
for `application/x-www-form-urlencoded` requests.

#### POST HTML form HTTP redirect

201 POST response is rewritten to a 303 with the `routes.get` URI as location.

#### PUT HTML form template

200 PUT response and GET of a resource shares the same URI and JSON structure, e.g. `/entity/3`
and `{"entity":{"name":"an entity"}}`.

GET returns an editable detail form of the entitiy with an hidden input field.
```html
<form action="{*data.entity.routes.put*}" method="post">
  <input name="method" type="hidden" value="put">
  <input required name="subject" value="{{data.entity.name}}">
  <button type="submit">Save</button>
</form>
```

The Nginx route changes this POST into a PUT request and finally uses the URI to find
and render a template of the updated entity.

#### DELETE HTML form template and redirect

A 204 DELETE response is rewritten to a 303 with the `routes.next` URI as location.

DELETE request requires an additional HTML form. A possible convention is the `/delete` path suffix.
```html
<form action="{*data.routes.confirm*}" method="post">
  <input name="method" type="hidden" value="delete">
  <button type="submit">Yes</button>
</form>
```

[postgres]: http://www.postgresql.org/
[pg_apt]: http://wiki.postgresql.org/wiki/Apt
[openresty]: http://openresty.org/
[lua-resty-template]: https://github.com/bungle/lua-resty-template

