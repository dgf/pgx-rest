SET search_path TO tasks, rest, public;

-- create test accounts
SELECT add_user('icke', 'secret', 'test user', '{"admin","user"}');
SELECT add_user('er', 'secret', 'test user', '{"user"}');
SELECT create_task('todo', 'something');

