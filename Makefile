#!make
include .env
export $(shell sed 's/=.*//' .env)

# Provides a bash in PHP container (user www-data)
bash-php: up
	docker-compose exec -u www-data php bash

# Provides a bash in PHP container (user root)
bash-php-root: up
	docker-compose exec php bash

install-complete: configure-wordpress
	gh auth login
	rm -rf .git
	gh repo create ${PROJECT_REPO} --private -y
	rm -rf ${PROJECT_REPO}
	git clone git@github.com:${GITHUB_NAME}/${PROJECT_REPO}
	mv ${PROJECT_REPO}/.git ./
	rm -rf ${PROJECT_REPO}
	git add .
	git commit -m "Initial import"
	git push origin master


# Build app
configure-wordpress: build composer-install

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
	docker-compose exec --user www-data php wp plugin install cookie-notice --activate
	docker-compose exec --user www-data php wp plugin install backwpup --activate
	docker-compose exec --user www-data php wp plugin install contact-form-7 --activate
	docker-compose exec --user www-data php wp plugin install popups-for-divi --activate
	docker-compose exec --user www-data php wp plugin install popup-maker --activate

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
