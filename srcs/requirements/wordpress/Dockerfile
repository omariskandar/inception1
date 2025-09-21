# srcs/requirements/wordpress/Dockerfile
FROM alpine:3.21

# PHP-FPM + extensions + tools
RUN apk add --no-cache \
  php82 php82-fpm php82-opcache php82-mysqli php82-json php82-session php82-curl \
  php82-dom php82-xml php82-xmlwriter php82-zip php82-mbstring php82-gd php82-phar \
  php82-iconv php82-tokenizer php82-cli \
  curl bash ca-certificates tar

# Symlink php → php82 for wp-cli
RUN ln -sf /usr/bin/php82 /usr/bin/php && php -v

# Install wp-cli
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
 && chmod +x /usr/local/bin/wp \
 && /usr/local/bin/wp --info --allow-root

# Web root & ownership (php-fpm on Alpine runs as 'nobody')
RUN mkdir -p /var/www/html && chown -R nobody:nogroup /var/www/html

# php-fpm pool config
COPY conf/www.conf /etc/php82/php-fpm.d/www.conf

# Entry setup
COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

WORKDIR /var/www/html
ENV WP_CLI_ALLOW_ROOT=1
EXPOSE 9000

CMD ["/usr/local/bin/setup.sh"]
