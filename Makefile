db_name=rest_check

# helper

init:
	createdb $(db_name)

cli:
	psql $(db_name)

setup:
	psql $(db_name) -f setup.sql

# base

clean:
	psql $(db_name) -f clean.sql

rest: clean
	psql $(db_name) -f rest.sql

# modules

tasks: rest
	psql $(db_name) -f modules/tasks.sql

contacts: rest
	psql $(db_name) -f modules/contacts.sql

dashboard: contacts tasks
	psql $(db_name) -f modules/dashboard.sql

# testing

test: dashboard
	psql $(db_name) -f specs/rest.sql
	psql $(db_name) -f specs/tasks.sql

application: dashboard
	psql $(db_name) -f usage.sql

