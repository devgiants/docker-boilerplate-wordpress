FROM ubuntu:16.04

MAINTAINER Nicolas BONNIOT <nicolas@devgiants.fr>

ARG UID

RUN apt-get update && apt-get install -y apache2

# Enable apache modules
RUN a2enmod proxy_fcgi
RUN a2enmod rewrite

ADD app.conf /etc/apache2/sites-available/
RUN a2ensite app

# Ensure old PID due to previous usage are killed
RUN rm -f /var/run/apache2/apache2.pid

EXPOSE 80

RUN usermod -u ${UID} www-data

WORKDIR /var/www/html

CMD /usr/sbin/apache2ctl -D FOREGROUND
