db_name = rest_check

# helper

targets:	# list all targets
	@grep '^[^#[:space:]].*:' Makefile

init: 		# create database
	createdb $(db_name)

cli: 		# connect Postgres terminal
	psql $(db_name)

setup:		# setup Postgres extensions
	psql $(db_name) -f setup.sql

# base

clean:		# clean database
	psql $(db_name) -f clean.sql

rest: clean	# install REST schema
	psql $(db_name) -f rest.sql

# testing
SPECS = rest tasks contacts application

test: application # run specifations
	$(foreach spec, $(SPECS), psql $(db_name) -f specs/$(spec).sql 2>&1 | ./reporter.awk;)

# modules

tasks: rest
	psql $(db_name) -f modules/tasks.sql

contacts: rest
	psql $(db_name) -f modules/contacts.sql

application: tasks contacts
	psql $(db_name) -f modules/application.sql

