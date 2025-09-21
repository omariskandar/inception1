# srcs/requirements/nginx/Dockerfile
FROM alpine:3.21

RUN apk add --no-cache nginx openssl bash

# Create dirs
RUN mkdir -p /run/nginx /etc/nginx/ssl /var/www/html

# Nginx config
COPY conf/nginx.conf /etc/nginx/nginx.conf

# Cert generation helper (self-signed if none mounted)
COPY tools/generate_cert.sh /usr/local/bin/generate_cert.sh
RUN chmod +x /usr/local/bin/generate_cert.sh

WORKDIR /var/www/html
EXPOSE 443

CMD ["/bin/bash", "-lc", "/usr/local/bin/generate_cert.sh && exec nginx -g 'daemon off;'"]
