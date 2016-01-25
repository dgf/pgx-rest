-- cleanup in reverse order, this also documents the API top down
DROP FUNCTION IF EXISTS call(c_method text, c_path text, c_session uuid, body json);
DROP FUNCTION IF EXISTS find_template(r_mime text, r_path text, OUT path text, OUT locals json);
DROP FUNCTION IF EXISTS login(u_login text, u_basic_auth text);
DROP FUNCTION IF EXISTS post_login(u_login text, u_password text);
DROP FUNCTION IF EXISTS post_logout(c_session uuid);

DROP SCHEMA application CASCADE;
DROP SCHEMA contacts CASCADE;
DROP SCHEMA tasks CASCADE;
DROP SCHEMA files CASCADE;
DROP SCHEMA rest CASCADE;

