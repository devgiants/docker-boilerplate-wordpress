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

# Force restart
docker-compose stop

# Copy WP-cli.yml with env var substitution
envsubst < ./wp-cli.yml > ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-cli.yml

# Restart containers
docker-compose up -d

# Install WP
docker-compose exec --user www-data php wp core download

# Create wp-config using wp-cli.yml file
docker-compose exec --user www-data php wp config create

# Create database - not needed here because of docker-compose creation
#docker-compose exec --user www-data php wp db create

# Install site
docker-compose exec --user www-data php wp core install

# TODO Install ACF pro https://github.com/wp-premium/advanced-custom-fields-pro/archive/master.zip

# install plugins
#while read line
#do
#    docker-compose exec --user www-data php wp plugin install $line --activate
#done < ./plugins.txt

docker-compose exec --user www-data php wp plugin install wordpress-seo --activate
docker-compose exec --user www-data php wp plugin install better-wp-security --activate
docker-compose exec --user www-data php wp plugin install ga-google-analytics --activate
docker-compose exec --user www-data php wp plugin install pixelyoursite --activate

# Clean tedious elements
docker-compose exec --user www-data php wp post delete 1 --force
docker-compose exec --user www-data php wp post delete 2 --force
docker-compose exec --user www-data php wp plugin delete hello

# Set permalinks to postname
docker-compose exec --user www-data php wp rewrite structure "/%postname%/" --hard
docker-compose exec --user www-data php wp rewrite flush --hard

# Install Roots Sage
docker-compose exec --user www-data php composer create-project roots/sage ${PROJECT_NAME} 8.5.3

# Move theme in theme folder
docker-compose exec --user www-data php mv ${PROJECT_NAME} wp-content/themes

# Activate sage theme
docker-compose exec --user www-data php wp theme activate ${PROJECT_NAME}

# Remove standard themes
docker-compose exec --user www-data php wp theme delete twentyfifteen twentysixteen twentyseventeen

# First compilation
cd ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-content/themes/${PROJECT_NAME}

npm install
bower install
gulp --production

