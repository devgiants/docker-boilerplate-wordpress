# Image plus récente et légère que Ubuntu full, tout en gardant le layout Apache "apache2"
FROM debian:bookworm-slim

ARG UID=33

ENV DEBIAN_FRONTEND=noninteractive

# Installer Apache avec le strict nécessaire, activer modules, nettoyer APT
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends apache2 ca-certificates; \
    a2enmod proxy_fcgi rewrite; \
    rm -rf /var/lib/apt/lists/*

# Copier la conf de vhost (préfère COPY à ADD)
COPY app.conf /etc/apache2/sites-available/app.conf

# Activer le site (et, si besoin, désactiver le défaut)
RUN set -eux; \
    a2dissite 000-default || true; \
    a2ensite app

# (Optionnel) Ajuster l'UID de www-data si tu montes des volumes avec des permissions spécifiques
# Note: modifier un UID dans une image peut avoir des effets sur des fichiers déjà possédés par www-data.
RUN set -eux; \
    if [ "${UID}" != "33" ]; then usermod -u "${UID}" www-data; fi

EXPOSE 80
WORKDIR /var/www/html

# Nettoyage PID au démarrage (utile si /var/run est persisté ou si redémarrages atypiques)
CMD ["/bin/sh", "-c", "rm -f /var/run/apache2/apache2.pid && exec apache2ctl -D FOREGROUND"]
