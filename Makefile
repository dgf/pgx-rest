db_name=rest_check

init:
	createdb $(db_name)

cli:
	psql $(db_name)

clean:
	psql $(db_name) -f clean_api.sql

rest: clean
	psql $(db_name) -f rest.sql

template: rest
	psql $(db_name) -f template.sql

tasks: template
	psql $(db_name) -f tasks.sql

contacts: template
	psql $(db_name) -f contacts.sql

dashboard: contacts tasks
	psql $(db_name) -f dashboard.sql

test: dashboard
	psql $(db_name) -f specs.sql

