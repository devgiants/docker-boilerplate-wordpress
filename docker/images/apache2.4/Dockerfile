FROM ubuntu:16.10

MAINTAINER Nicolas BONNIOT <nicolas@devgiants.fr>

ARG UID

RUN apt-get update && apt-get install -y apache2

# Enable apache modules
RUN a2enmod proxy_fcgi
RUN a2enmod rewrite

ADD app.conf /etc/apache2/sites-available/
RUN a2ensite app

EXPOSE 80

RUN usermod -u ${UID} www-data

WORKDIR /var/www/html

CMD /usr/sbin/apache2ctl -D FOREGROUND
