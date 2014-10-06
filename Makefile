db_name=rest_check

init:
	createdb $(db_name)

setup:
	psql $(db_name) -f setup.sql

cli:
	psql $(db_name)

clean:
	psql $(db_name) -f clean_api.sql

rest: clean
	psql $(db_name) -f rest.sql

tasks: rest
	psql $(db_name) -f tasks.sql

contacts: rest
	psql $(db_name) -f contacts.sql

dashboard: contacts tasks
	psql $(db_name) -f dashboard.sql

test: dashboard
	psql $(db_name) -f specs.sql

