# srcs/requirements/wordpress/Dockerfile
FROM alpine:3.21

# php-fpm + needed extensions + tools + WP-CLI
RUN apk add --no-cache \
  php82 php82-fpm php82-opcache php82-mysqli php82-json php82-session php82-curl \
  php82-dom php82-xml php82-xmlwriter php82-zip php82-mbstring php82-gd php82-phar \
  php82-iconv php82-tokenizer php82-pecl-redis \
  php82-cli curl tar bash ca-certificates mysql-client

# Symlink php -> php82
RUN ln -sf /usr/bin/php82 /usr/bin/php && php -v

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp \
    && wp --version

# Create www-data user and group (WordPress runs as www-data)
RUN adduser -S www-data -G www-data

# web root with proper permissions
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html

# php-fpm pool config
COPY conf/www.conf /etc/php82/php-fpm.d/www.conf

# setup script (downloads/configures WordPress and users)
COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

WORKDIR /var/www/html

# Health check
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
    CMD nc -z localhost 9000 || exit 1

EXPOSE 9000

# Start PHP-FPM and run setup
CMD ["sh", "-c", "/usr/local/bin/setup.sh && php-fpm82 -F"]