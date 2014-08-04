# REST on PostgreSQL

This is a test implementation of REST compatible endpoints with PostgreSQL functions.
And yes, it feels right! IMO there is no better solution to achieve this.

To start a ROCA based application, with a backend like this, you only need an
environment with a HTTP server and a PostgreSQL interface - that's it!

Requirements: only PostgreSQL 9.4 or higher

## Installation

To install an actual [PostgreSQL][postgres] on Ubuntu or Debian follow these [instructions][pg_apt]
and use a tagged repository to overrule the libpg version.

    deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main 9.4

## Setup

Define a database name in the Makefile or use `rest_check` (the default).

create a fresh database
```sh
$ make init
```

import all examples
```sh
$ make dashboard
```

## Usage

The example application ships a simple task and contact management with a dashboard.

start a psql client connection
```sh
make cli
```

list all existing routes
```SQL
SELECT method, path, proc, description FROM route ORDER by path, method;
 method |          path          |        proc         |      description       
--------+------------------------+---------------------+------------------------
 post   | /contact               | post_contact        | create a contact
 get    | /contact/{id}          | get_contact         | contact details
 put    | /contact/{id}          | put_contact         | update contact details
 delete | /contact/{id}          | delete_contact      | delete a contact
 put    | /contact/{id}/address  | put_contact_address | update contact address
 get    | /contacts              | get_contacts        | contact list
 get    | /dashboard             | get_dashboard       | index page
 post   | /task                  | post_task           | create a task
 put    | /task/{id}             | put_task            | update a task
 delete | /task/{id}             | delete_task         | delete a task
 post   | /task/{id}/cancel      | post_task_cancel    | cancel a task
 post   | /task/{id}/finish      | post_task_finish    | finish a task
 post   | /task/{id}/reopen      | post_task_reopen    | reopen a task
 get    | /tasks                 | get_tasks           | all tasks
 get    | /tasks?status={status} | get_tasks           | filter tasks
(15 rows)
```

create a new task
```SQL
SELECT post('/task', '{"subject": "todo", "description": "something"}'::json);
                                           post                                            
-------------------------------------------------------------------------------------------
 (201,"{""id"":1,""status"":""open"",""subject"":""todo"",""description"":""something""}")
(1 row)
```

get all open tasks
```SQL
SELECT data FROM get('/tasks?status=open');
                                 data                                  
-----------------------------------------------------------------------
 [{"id":1,"status":"open","subject":"todo","description":"something"}]
(1 row)
```

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
INSERT INTO route (method, path, proc, description)
VALUES ('get', '/entities', 'get_entities', 'entity list');
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

create an application user with login
```SQL
CREATE USER application WITH NOINHERIT ENCRYPTED PASSWORD 'SecreT';
GRANT ALL ON ALL TABLES IN SCHEMA public to application;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public to application;
```

adjust credentials in `nginx.conf`
```sh
$ grep postgres_server nginx.conf
    postgres_server 127.0.0.1 dbname=rest_check user=application password=SecreT;
```

start Nginx
```sh
$ nginx -p `pwd`/ -c nginx.conf
``` 

a simple task flow example session
```sh
# create a task
$ curl -D - -d '{"subject":"todo", "description":"something"}' http://localhost:8080/task
HTTP/1.1 201 Created
Server: openresty/1.7.2.1
Date: Mon, 04 Aug 2014 18:03:29 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{"id":1,"status":"open","subject":"todo","description":"something"}%    

# list all open tasks
$ curl -D - http://localhost:8080/tasks\?status\=open
HTTP/1.1 200 OK
Server: openresty/1.7.2.1
Date: Mon, 04 Aug 2014 18:05:09 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

[{"id":1,"status":"open","subject":"todo","description":"something"}]% 

# finish the task
$ curl -D - -X POST http://localhost:8080/task/1/finish
HTTP/1.1 200 OK
Server: openresty/1.7.2.1
Date: Mon, 04 Aug 2014 18:06:07 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive

{"id":1,"status":"done","subject":"todo","description":"something"}% 

# there are no open tasks
$ curl -D - http://localhost:8080/tasks\?status\=open
HTTP/1.1 205 
Server: openresty/1.7.2.1
Date: Mon, 04 Aug 2014 18:37:38 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
```

[openresty]: http://openresty.org/
[postgres]: http://www.postgresql.org/
[pg_apt]: http://wiki.postgresql.org/wiki/Apt

