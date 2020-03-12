#!make
include .env
export $(shell sed 's/=.*//' .env)

# Provides a bash in PHP container (user www-data)
bash-php: up
	docker-compose exec -u www-data php bash

# Provides a bash in PHP container (user root)
bash-php-root: up
	docker-compose exec php bash

sage: install
	# Install Roots Sage
	docker-compose exec --user www-data php composer create-project roots/sage ${PROJECT_NAME} 9.0.9

	# First compilation
	# cd ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-content/themes/${PROJECT_NAME}

	# Move theme in theme folder
	docker-compose exec --user www-data php mv ${PROJECT_NAME} wp-content/themes

	# Install nodes modules
	docker-compose exec --user www-data php yarn install --cwd ${WORDPRESS_HOST_RELATIVE_APP_PATH}wp-content/themes/${PROJECT_NAME}


	docker-compose exec --user www-data php bash -c "cd ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-content/themes/${PROJECT_NAME} && yarn run build"

	# Build sage theme composer
	docker-compose exec --user www-data php bash -c "cd ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-content/themes/${PROJECT_NAME} && composer install"

	# Activate sage theme
	docker-compose exec --user www-data php wp theme activate ${PROJECT_NAME}

	# Remove standard themes
	docker-compose exec --user www-data php wp theme delete twentysixteen twentyseventeen twentynineteen

# Build app
install: build composer-install

	set -o allexport
	. ./.env
	set +o allexport

	# Substitute env vars in files
	envsubst < ./wp-cli.yml.dist > ./wp-cli.yml
	envsubst < ./deploy.php.dist > ./deploy.php
	rm ./wp-cli.yml.dist ./deploy.php.dist

	# Install WP
	docker-compose exec --user www-data php wp core download

	# Create wp-config using wp-cli.yml file
	docker-compose exec --user www-data php wp config create

	# Install site
	docker-compose exec --user www-data php wp core install

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


build-assets: up
	docker-compose exec --user www-data php bash -c "cd ${WORDPRESS_HOST_RELATIVE_APP_PATH}/wp-content/themes/${PROJECT_NAME} && yarn install && yarn build:production"

composer-install: up
	# Install PHP dependencies
	docker-compose exec -u www-data php composer install


# Up containers
up:
	docker-compose up -d
	docker-compose exec php usermod -u ${HOST_UID} www-data
	docker-compose exec apache usermod -u ${HOST_UID} www-data

# Up containers, with build forced
build:
	docker-compose up -d --build
	docker-compose exec php usermod -u ${HOST_UID} www-data
	docker-compose exec apache usermod -u ${HOST_UID} www-data

# Down containers
down:
	docker-compose down
