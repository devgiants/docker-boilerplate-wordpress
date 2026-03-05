set dotenv-load := true
set export := true

# Optional local overlays for private/non-versioned recipes.
import? 'justfile.local'
import? 'justfile.private'
import? 'justfile.user'

# Provides a bash in PHP container (user www-data)
bash-php: up
    docker compose exec -u www-data php bash

# Provides a bash in PHP container (user root)
bash-php-root: up
    docker compose exec php bash

update-all: update-core update-plugins update-themes update-translations
    @true

update-core: up
    docker compose exec -u www-data php wp core update
    rm -rf wp-content/themes/twenty*
    git add . && git commit -m "Update core"

update-plugins: up
    docker compose exec -u www-data php wp plugin update --all --exclude=backwpup
    git add . && git commit -m "Update plugins"

update-themes: up
    # Force refresh of theme update metadata so premium updates (e.g. Divi) are detected immediately.
    docker compose exec -u www-data php wp eval 'delete_site_transient("update_themes"); wp_clean_themes_cache(true); wp_update_themes();'
    docker compose exec -u www-data php wp theme update --all
    git add . && git commit -m "Update themes"

update-translations: up
    docker compose exec -u www-data php wp language core update
    docker compose exec -u www-data php wp language plugin update --all
    docker compose exec -u www-data php wp language theme update --all
    git add . && git commit -m "Update translations"

set-uploads-permissions: up
    # Acceptable tradeoff for security and ease of use in development environment, 
    # especially when using containers with both sides writing to the same files.
    # In production, you should set more restrictive permissions.
    sudo chmod -R 775 wp-content/uploads
    sudo chown -R ${HOST_USER}:www-data wp-content/uploads

install-and-version: configure-wordpress
    # You must be logged in first with gh auth login
    rm -rf .git
    gh repo create ${PROJECT_REPO} --private -y
    rm -rf ${PROJECT_REPO}
    git clone git@github.com:${GITHUB_NAME}/${PROJECT_REPO}
    mv ${PROJECT_REPO}/.git ./
    rm -rf ${PROJECT_REPO}
    git add .
    git commit -m "Initial import"
    git push origin main

wait-db:
    @echo "Waiting for database to be ready..."
    @bash -c 'until docker compose exec -T mysql mariadb-admin ping -h localhost --silent; do echo "still waiting..."; sleep 2; done'
    @echo "Database is up!"

# Build app
configure-wordpress: build wait-db
    # Substitute env vars in files
    envsubst < ./wp-cli.yml.dist > ./wp-cli.yml
    envsubst < ./deploy.php.dist > ./deploy.php
    rm ./wp-cli.yml.dist ./deploy.php.dist

    # Install WP
    docker compose exec --user www-data php wp core download

    # Create wp-config using wp-cli.yml file
    docker compose exec --user www-data php wp config create

    # Install site
    docker compose exec --user www-data php wp core install

    docker compose exec --user www-data php wp option set siteurl http://localhost:${APPLICATION_WEB_PORT}
    docker compose exec --user www-data php wp option set home http://localhost:${APPLICATION_WEB_PORT}

    docker compose exec --user www-data php wp plugin install wordpress-seo --activate
    docker compose exec --user www-data php wp plugin install better-wp-security --activate
    docker compose exec --user www-data php wp plugin install cookie-notice --activate
    docker compose exec --user www-data php wp plugin install backwpup --activate --version=4.1.7
    docker compose exec --user www-data php wp plugin install wp-piwik --activate
    docker compose exec --user www-data php wp plugin install popups-for-divi --activate
    docker compose exec --user www-data php wp plugin install popup-maker --activate
    docker compose exec --user www-data php wp plugin install post-duplicator --activate
    docker compose exec --user www-data php wp plugin install supreme-modules-for-divi --activate
    docker compose exec --user www-data php wp plugin install wp-mail-smtp --activate
    docker compose exec --user www-data php wp plugin install disable-comments --activate

    # Clean tedious elements
    docker compose exec --user www-data php wp post delete 1 --force
    docker compose exec --user www-data php wp post delete 2 --force
    docker compose exec --user www-data php wp plugin delete hello

    # Set permalinks to postname
    docker compose exec --user www-data php wp rewrite structure "/%postname%/" --hard
    docker compose exec --user www-data php wp rewrite flush --hard

    # Add config parameters
    docker compose exec --user www-data php wp config set WP_AUTO_UPDATE_CORE false --raw
    docker compose exec --user www-data php wp config set WP_POST_REVISIONS 5 --raw

search-replace: up
    SITE_URL=$(docker compose exec --user www-data php wp option get siteurl) && docker compose exec --user www-data php wp search-replace "$SITE_URL" "http://localhost:${APPLICATION_WEB_PORT}"

# Set Divi update credentials in WordPress options table.
# Requires DIVI_USERNAME and DIVI_API_KEY in environment or .env.
set-divi-api-key: up
    @if [ -z "${DIVI_USERNAME:-}" ] || [ -z "${DIVI_API_KEY:-}" ]; then echo "DIVI_USERNAME and DIVI_API_KEY must be set (env or .env)." && exit 1; fi
    docker compose exec -e DIVI_USERNAME="${DIVI_USERNAME}" -e DIVI_API_KEY="${DIVI_API_KEY}" --user www-data php wp --skip-themes --skip-plugins eval '$value = get_option("et_automatic_updates_options"); if (!is_array($value)) { $value = []; } $value["username"] = getenv("DIVI_USERNAME"); $value["api_key"] = getenv("DIVI_API_KEY"); update_option("et_automatic_updates_options", $value);'
    docker compose exec --user www-data php wp --skip-themes --skip-plugins option get et_automatic_updates_options --format=json

# Destroy local stack and data, then delete remote GitHub repository.
# Requires gh authentication.
erase-all:
    @bash -c 'echo "WARNING: This will remove compose containers/volumes and delete ${GITHUB_NAME}/${PROJECT_REPO} on GitHub."; printf "Type YES to continue: "; read -r confirm; [ "$confirm" = "YES" ] || { echo "Aborted."; exit 1; }'
    @if [ -z "${GITHUB_NAME:-}" ] || [ -z "${PROJECT_REPO:-}" ]; then echo "GITHUB_NAME and PROJECT_REPO must be set."; exit 1; fi
    docker compose down --volumes --remove-orphans
    @if gh repo view "${GITHUB_NAME}/${PROJECT_REPO}" >/dev/null 2>&1; then gh repo delete "${GITHUB_NAME}/${PROJECT_REPO}" --yes; else echo "GitHub repo ${GITHUB_NAME}/${PROJECT_REPO} not found, skipping."; fi

# Up containers
up:
    docker compose up -d --wait

# Up containers, with build forced
build:
    docker compose up -d --build

# Down containers
down:
    docker compose down
