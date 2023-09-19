#!make
include .env
export $(shell sed 's/=.*//' .env)

# Provides a bash in PHP container (user www-data)
bash-php: up
	docker-compose exec -u www-data php bash

# Provides a bash in PHP container (user root)
bash-php-root: up
	docker-compose exec php bash

update-all: update-core update-plugins update-themes update-translations

update-core: up
	docker-compose exec -u www-data php wp core update
	rm -rf wp-content/themes/twenty*
	git add . && git commit -m "Update core"

update-plugins: up
	docker-compose exec -u www-data php wp plugin update --all
	git add . && git commit -m "Update plugins"

update-themes: up
	docker-compose exec -u www-data php wp theme update --all
	git add . && git commit -m "Update themes"

update-translations: up
	docker-compose exec -u www-data php wp language core update
	docker-compose exec -u www-data php wp language plugin update --all
	docker-compose exec -u www-data php wp language theme update --all
	git add . && git commit -m "Update translations"

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
configure-wordpress: build

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
	docker-compose exec --user www-data php wp plugin install wp-piwik --activate
	docker-compose exec --user www-data php wp plugin install popups-for-divi --activate
	docker-compose exec --user www-data php wp plugin install popup-maker --activate
	docker-compose exec --user www-data php wp plugin install post-duplicator --activate
	docker-compose exec --user www-data php wp plugin install supreme-modules-for-divi --activate

	# Clean tedious elements
	docker-compose exec --user www-data php wp post delete 1 --force
	docker-compose exec --user www-data php wp post delete 2 --force
	docker-compose exec --user www-data php wp plugin delete hello

	# Set permalinks to postname
	docker-compose exec --user www-data php wp rewrite structure "/%postname%/" --hard
	docker-compose exec --user www-data php wp rewrite flush --hard

	# Add config parameters
	docker-compose exec --user www-data php wp config set WP_AUTO_UPDATE_CORE false --raw
	docker-compose exec --user www-data php wp config set WP_POST_REVISIONS 5 --raw
	docker-compose exec --user www-data php wp config set WP_DEBUG true --raw

search-replace: up
	docker-compose exec --user www-data php wp search-replace `docker-compose exec --user www-data php wp option get siteurl` 'http://localhost:${APPLICATION_WEB_PORT}'

# Up containers
up:
	docker-compose up -d

# Up containers, with build forced
build:
	docker-compose up -d --build

# Down containers
down:
	docker-compose down
