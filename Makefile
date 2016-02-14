# configuration
db_name = rest_check
ng_version = 1.9.7.2

# commands
curl = /usr/bin/curl
nginx = /usr/local/openresty/nginx/sbin/nginx

# helper

targets:                # list all targets
	@grep '^[^#[:space:]].*:.*#' Makefile

cli:                    # connect Postgres terminal
	psql $(db_name)

# modules

tasks: rest
	psql $(db_name) -f modules/tasks.sql

files: rest
	psql $(db_name) -f modules/files.sql

contacts: rest
	psql $(db_name) -f modules/contacts.sql

app: files tasks contacts
	psql $(db_name) -f modules/application.sql

# base

clean:                  # clean database
	psql $(db_name) -f clean.sql

rest: clean             # install REST schema
	psql $(db_name) -f rest.sql

install: rest app       # install example application
# testing

SPECS = rest files tasks contacts application

test: app               # run specifications
	$(foreach spec, $(SPECS), psql $(db_name) -f specs/$(spec).sql 2>&1 | ./reporter.awk;)

# setup

init:                   # create database
	createdb $(db_name)

pg-setup:               # setup Postgres extensions
	psql $(db_name) -f setup.sql

ng-download:            # fetch and unpack Nginx
	cd build && \
	curl http://openresty.org/download/ngx_openresty-${ng_version}.tar.gz | tar xzv

ng-compile: ng-download # compile Nginx
	cd build/ngx_openresty-${ng_version} && \
	./configure \
	  --with-http_postgres_module \
	  --with-luajit \
	  --without-http_autoindex_module \
	  --without-http_fastcgi_module \
	  --without-http_lua_upstream_module \
	  --without-http_map_module \
	  --without-http_memcached_module \
	  --without-http_memc_module \
	  --without-http_proxy_module \
	  --without-http_redis2_module \
	  --without-http_redis_module \
	  --without-http_scgi_module \
	  --without-http_split_clients_module \
	  --without-http_ssi_module \
	  --without-http_upstream_ip_hash_module \
	  --without-http_userid_module \
	  --without-http_uwsgi_module \
	  --without-lua51 \
	  --without-lua_redis_parser \
	  --without-lua_resty_memcached \
	  --without-lua_resty_mysql \
	  --without-lua_resty_redis \
	  --without-lua_resty_upstream_healthcheck \
	  --without-mail_imap_module \
	  --without-mail_pop3_module \
	  --without-mail_smtp_module && \
	make

ng-install: ng-compile  # install Nginx
	cd build/ngx_openresty-${ng_version} && \
	sudo make install

ng-run:                 # start Nginx
	${nginx} -p `pwd`/ -c nginx.conf
