FROM debian:bookworm-slim

ARG UID=33

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends apache2 ca-certificates; \
    a2enmod proxy_fcgi rewrite; \
    rm -rf /var/lib/apt/lists/*

COPY app.conf /etc/apache2/sites-available/app.conf

RUN set -eux; \
    a2dissite 000-default || true; \
    a2ensite app

RUN set -eux; \
    if [ "${UID}" != "33" ]; then usermod -u "${UID}" www-data; fi

EXPOSE 80
WORKDIR /var/www/html

CMD ["/bin/sh", "-c", "rm -f /var/run/apache2/apache2.pid && exec apache2ctl -D FOREGROUND"]
