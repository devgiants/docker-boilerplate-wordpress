#!/usr/bin/env bash

set -o allexport
source ./.env
set +o allexport

# Create mysql volume target dir if not exists already, and set it as current user (needed for container mapping)
mkdir -p ${MYSQL_HOST_VOLUME_PATH}
sudo chown -R ${HOST_USER}:${HOST_USER} ${MYSQL_HOST_VOLUME_PATH}
sudo chmod -R 775 ${MYSQL_HOST_VOLUME_PATH}

# Create target dir if not exists already, and set it as current user (needed for container mapping)
mkdir -p ${WORDPRESS_HOST_RELATIVE_APP_PATH}
sudo chown -R ${HOST_USER}:${HOST_USER} ${WORDPRESS_HOST_RELATIVE_APP_PATH}
sudo chmod -R 775 ${WORDPRESS_HOST_RELATIVE_APP_PATH}

# Build and live system
docker-compose up -d --build

# Copy WP-cli.yml with env var substitution
envsubst < ./wp-cli.yml > ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-cli.yml


# Install WP
docker-compose exec -u www-data php wp core download

# Create wp-config using wp-cli.yml file
docker-compose exec -u www-data php wp config create

# Create database
docker-compose exec -u www-data php wp db create

# Install site
docker-compose exec -u www-data php wp core install

# TODO Install ACF pro https://github.com/wp-premium/advanced-custom-fields-pro/archive/master.zip

# install plugins
while read line
do
    docker-compose exec -u www-data php wp plugin install $line --activate
done < ./plugins.txt

# Clean tedious elements
docker-compose exec -u www-data php wp post delete 1 --force
docker-compose exec -u www-data php wp post delete 2 --force
docker-compose exec -u www-data php wp plugin delete hello

# Set permalinks to postname
docker-compose exec -u www-data php wp rewrite structure "/%postname%/" --hard
docker-compose exec -u www-data php wp rewrite flush --hard

# TODO install Sage