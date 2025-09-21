# srcs/requirements/mariadb/Dockerfile
FROM alpine:3.21

RUN apk add --no-cache mariadb mariadb-client bash

# Create needed dirs with proper ownership
RUN mkdir -p /run/mysqld /var/lib/mysql && \
    chown -R mysql:mysql /run/mysqld /var/lib/mysql

# Config
COPY conf/my.cnf /etc/my.cnf

# Entry
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER mysql
EXPOSE 3306
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
