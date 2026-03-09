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
    git add -A
    @if ! git diff --cached --quiet; then git commit -m "Update core"; else echo "No core updates to commit."; fi

warmup-updates target='both' passes='5' sleep_seconds='2':
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{target}}"
    passes="{{passes}}"
    sleep_seconds="{{sleep_seconds}}"
    app_url="http://localhost:${APPLICATION_WEB_PORT}"

    if ! command -v curl >/dev/null 2>&1; then
      echo "curl not found, skipping HTTP warmup."
      exit 0
    fi

    if [[ -z "${ADMIN_USER:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
      echo "ADMIN_USER or ADMIN_PASSWORD missing, skipping HTTP warmup."
      exit 0
    fi

    if ! [[ "$passes" =~ ^[1-9][0-9]*$ ]]; then
      echo "Invalid warmup passes '$passes' (expected positive integer)."
      exit 1
    fi

    if ! [[ "$sleep_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      echo "Invalid warmup sleep_seconds '$sleep_seconds' (expected number)."
      exit 1
    fi

    case "$target" in
      plugins)
        admin_paths=("/${BO_URL}/" "/${BO_URL}/plugins.php" "/${BO_URL}/update-core.php")
        ;;
      themes)
        admin_paths=("/${BO_URL}/" "/${BO_URL}/themes.php" "/${BO_URL}/update-core.php")
        ;;
      both)
        admin_paths=("/${BO_URL}/" "/${BO_URL}/plugins.php" "/${BO_URL}/themes.php" "/${BO_URL}/update-core.php")
        ;;
      *)
        echo "Invalid warmup target '$target' (expected plugins|themes|both)."
        exit 1
        ;;
    esac

    front_paths=("/")
    cookie_file="$(mktemp)"
    cleanup() {
      rm -f "$cookie_file"
    }
    trap cleanup EXIT

    request_url() {
      local url="$1"
      local mode="${2:-public}"
      local http_code

      if [[ "$mode" == "auth" ]]; then
        http_code="$(curl -sS -L -o /dev/null -w "%{http_code}" -b "$cookie_file" -c "$cookie_file" "$url" || echo "000")"
      else
        http_code="$(curl -sS -L -o /dev/null -w "%{http_code}" "$url" || echo "000")"
      fi

      if [[ "$http_code" == "404" ]]; then
        echo "HTTP 404 during warmup: $url"
      elif [[ "$http_code" =~ ^[45][0-9][0-9]$ ]]; then
        echo "HTTP $http_code during warmup: $url"
      fi
    }

    if ! curl -fsS -c "$cookie_file" "${app_url}/wp-login.php" >/dev/null; then
      echo "Unable to reach wp-login.php, skipping HTTP warmup."
      exit 0
    fi

    if ! curl -fsS -L -b "$cookie_file" -c "$cookie_file" \
      --data-urlencode "log=${ADMIN_USER}" \
      --data-urlencode "pwd=${ADMIN_PASSWORD}" \
      --data-urlencode "rememberme=forever" \
      --data-urlencode "wp-submit=Log In" \
      --data-urlencode "redirect_to=${app_url}/${BO_URL}/" \
      --data-urlencode "testcookie=1" \
      "${app_url}/wp-login.php" >/dev/null; then
      echo "Admin login request failed, skipping HTTP warmup."
      exit 0
    fi

    if ! grep -q "wordpress_logged_in_" "$cookie_file"; then
      echo "Admin login cookie not found, skipping HTTP warmup."
      exit 0
    fi

    for pass in $(seq 1 "$passes"); do
      echo "HTTP warmup pass ${pass}/${passes} (${target})..."

      for path in "${admin_paths[@]}"; do
        request_url "${app_url}${path}" auth
      done

      for path in "${front_paths[@]}"; do
        request_url "${app_url}${path}" public
      done

      request_url "${app_url}/wp-cron.php?doing_wp_cron=$(date +%s)" public
      docker compose exec -T -u www-data php wp cron event run --due-now >/dev/null 2>&1 || true

      sleep "$sleep_seconds"
    done

run-hook hook:
    #!/usr/bin/env bash
    set -euo pipefail
    hook="{{hook}}"
    if just --summary | tr ' ' '\n' | grep -qx "$hook"; then
      echo "Running hook: $hook"
      just "$hook"
    fi

update-plugins: up
    #!/usr/bin/env bash
    set -euo pipefail
    recheck_passes="${PLUGIN_UPDATE_RECHECK_PASSES:-${UPDATE_WARMUP_PASSES:-5}}"
    sleep_seconds="${UPDATE_WARMUP_SLEEP_SECONDS:-2}"
    just warmup-updates plugins "$recheck_passes" "$sleep_seconds"
    just run-hook update-plugins-pre-hook

    echo "Plugins with updates currently visible to WordPress:"
    docker compose exec -T -u www-data php wp plugin list --update=available || true

    docker compose exec -u www-data php wp plugin update --all --exclude=backwpup
    just run-hook update-plugins-post-hook

    git add -A
    if ! git diff --cached --quiet; then
      git commit -m "Update plugins"
    else
      echo "No plugin updates to commit."
    fi

update-themes: up
    #!/usr/bin/env bash
    set -euo pipefail
    recheck_passes="${THEME_UPDATE_RECHECK_PASSES:-${UPDATE_WARMUP_PASSES:-5}}"
    sleep_seconds="${UPDATE_WARMUP_SLEEP_SECONDS:-2}"
    just warmup-updates themes "$recheck_passes" "$sleep_seconds"
    just run-hook update-themes-pre-hook

    echo "Themes with updates currently visible to WordPress:"
    docker compose exec -T -u www-data php wp theme list --update=available || true

    docker compose exec -u www-data php wp theme update --all
    just run-hook update-themes-post-hook

    git add -A
    if ! git diff --cached --quiet; then
      git commit -m "Update themes"
    else
      echo "No theme updates to commit."
    fi

update-translations: up
    docker compose exec -u www-data php wp language core update
    docker compose exec -u www-data php wp language plugin update --all
    docker compose exec -u www-data php wp language theme update --all
    git add -A
    @if ! git diff --cached --quiet; then git commit -m "Update translations"; else echo "No translation updates to commit."; fi

set-uploads-permissions: up
    # Acceptable tradeoff for security and ease of use in development environment, 
    # especially when using containers with both sides writing to the same files.
    # In production, you should set more restrictive permissions.
    sudo chmod -R 775 wp-content/uploads
    sudo chown -R ${HOST_USER}:www-data wp-content/uploads

install-and-version:
    #!/usr/bin/env bash
    set -euo pipefail

    if docker compose exec -T --user www-data php wp core is-installed >/dev/null 2>&1; then
      echo "WordPress is already installed, skipping configure-wordpress."
    else
      just configure-wordpress
    fi

    # Enforce debug flags on every run, including already-installed stacks.
    docker compose exec --user www-data php wp config set WP_DEBUG false --raw
    docker compose exec --user www-data php wp config set WP_DEBUG_LOG false --raw

    if [[ -d .git ]]; then
      echo "Git repository already initialized, skipping GitHub bootstrap."
      exit 0
    fi

    if [[ -z "${GITHUB_NAME:-}" || -z "${PROJECT_REPO:-}" ]]; then
      echo "GITHUB_NAME and PROJECT_REPO must be set."
      exit 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
      echo "You must be logged in first with gh auth login."
      exit 1
    fi

    if gh repo view "${GITHUB_NAME}/${PROJECT_REPO}" >/dev/null 2>&1; then
      echo "GitHub repo ${GITHUB_NAME}/${PROJECT_REPO} already exists."
    else
      gh repo create "${PROJECT_REPO}" --private -y
    fi

    git init
    git checkout -B main
    git remote add origin "git@github.com:${GITHUB_NAME}/${PROJECT_REPO}"
    git add -A

    if ! git diff --cached --quiet; then
      git commit -m "Initial import"
    else
      git commit --allow-empty -m "Initial import"
    fi

    git push -u origin main

wait-db:
    @echo "Waiting for database to be ready..."
    @bash -c 'until docker compose exec -T mysql mariadb-admin ping -h localhost --silent; do echo "still waiting..."; sleep 2; done'
    @echo "Database is up!"

# Build app
configure-wordpress: build wait-db
    # Skip full bootstrap if WordPress is already installed.
    @if docker compose exec -T --user www-data php wp core is-installed >/dev/null 2>&1; then echo "WordPress already installed, skipping configure-wordpress."; exit 0; fi

    # Substitute env vars in files
    @if [ -f ./wp-cli.yml.dist ]; then envsubst < ./wp-cli.yml.dist > ./wp-cli.yml; rm ./wp-cli.yml.dist; fi
    @if [ -f ./deploy.php.dist ]; then envsubst < ./deploy.php.dist > ./deploy.php; rm ./deploy.php.dist; fi

    # Install WP
    docker compose exec --user www-data php wp core download

    # Create wp-config using wp-cli.yml file
    @if [ ! -f ./wp-config.php ]; then docker compose exec --user www-data php wp config create; else echo "wp-config.php already exists, skipping creation."; fi

    # Install site
    @if ! docker compose exec -T --user www-data php wp core is-installed >/dev/null 2>&1; then docker compose exec --user www-data php wp core install; else echo "WordPress already installed, skipping core install."; fi

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
    docker compose exec --user www-data php wp config set WP_DEBUG false --raw
    docker compose exec --user www-data php wp config set WP_DEBUG_LOG false --raw
    docker compose exec --user www-data php wp config set WP_AUTO_UPDATE_CORE false --raw
    docker compose exec --user www-data php wp config set WP_POST_REVISIONS 5 --raw



# Import a specific SQL dump file into MYSQL_DATABASE on container MYSQL_HOST.
import-db-file dump_file: up
    #!/usr/bin/env bash
    set -euo pipefail

    : "${MYSQL_HOST:?MYSQL_HOST is required}"
    : "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"

    dump_file="{{dump_file}}"
    if [[ ! -f "$dump_file" ]]; then
      echo "Dump file not found: ${dump_file}" >&2
      exit 1
    fi

    mysql_user="${MYSQL_USER:-root}"
    mysql_password="${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
    mysql_cmd=(mysql -u"${mysql_user}")
    if [[ -n "$mysql_password" ]]; then
      mysql_cmd=(mysql -u"${mysql_user}" "-p${mysql_password}")
    fi

    echo "Dropping existing tables in ${MYSQL_DATABASE} (if any)..."
    drop_sql=$'SET SESSION group_concat_max_len = 1000000;\nSET FOREIGN_KEY_CHECKS = 0;\nSET @tables = NULL;\nSELECT GROUP_CONCAT(CONCAT(\'`\', table_name, \'`\')) INTO @tables FROM information_schema.tables WHERE table_schema = DATABASE();\nSET @tables = IFNULL(@tables, \'\');\nSET @stmt = IF(@tables = \'\', \'SELECT 1\', CONCAT(\'DROP TABLE \', @tables));\nPREPARE drop_stmt FROM @stmt;\nEXECUTE drop_stmt;\nDEALLOCATE PREPARE drop_stmt;\nSET FOREIGN_KEY_CHECKS = 1;'
    docker compose exec -T "${MYSQL_HOST}" "${mysql_cmd[@]}" "${MYSQL_DATABASE}" -e "$drop_sql"

    echo "Importing ${dump_file} into ${MYSQL_DATABASE} on service ${MYSQL_HOST}..."
    if [[ "$dump_file" == *.sql.gz ]]; then
      zcat "$dump_file" | docker compose exec -T "${MYSQL_HOST}" "${mysql_cmd[@]}" "${MYSQL_DATABASE}"
    elif [[ "$dump_file" == *.sql ]]; then
      docker compose exec -T "${MYSQL_HOST}" "${mysql_cmd[@]}" "${MYSQL_DATABASE}" < "$dump_file"
    else
      echo "Unsupported dump format: ${dump_file} (expected .sql or .sql.gz)" >&2
      exit 1
    fi

    echo "Database import completed."

search-replace: up
    SITE_URL=$(docker compose exec --user www-data php wp option get siteurl) && docker compose exec --user www-data php wp search-replace "$SITE_URL" "http://localhost:${APPLICATION_WEB_PORT}"

# Set Divi update credentials in WordPress options table.
# Requires DIVI_USERNAME and DIVI_API_KEY in environment or .env.
set-divi-api-key: up
    @if [ -z "${DIVI_USERNAME:-}" ] || [ -z "${DIVI_API_KEY:-}" ]; then echo "DIVI_USERNAME and DIVI_API_KEY must be set (env or .env)." && exit 1; fi
    docker compose exec -e DIVI_USERNAME="${DIVI_USERNAME}" -e DIVI_API_KEY="${DIVI_API_KEY}" --user www-data php wp --skip-themes --skip-plugins eval '$user = getenv("DIVI_USERNAME"); $key = getenv("DIVI_API_KEY"); $value = get_option("et_automatic_updates_options"); if (!is_array($value)) { $value = []; } $value["username"] = $user; $value["api_key"] = $key; $value["apikey"] = $key; update_option("et_automatic_updates_options", $value); $epanel = get_option("et_epanel"); if (is_array($epanel)) { $epanel["et_username"] = $user; $epanel["et_api_key"] = $key; update_option("et_epanel", $epanel); }'
    docker compose exec --user www-data php wp --skip-themes --skip-plugins option get et_automatic_updates_options --format=json

# Destroy local stack and data, then delete remote GitHub repository.
# Requires gh authentication.
erase-all:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -z "${GITHUB_NAME:-}" || -z "${PROJECT_REPO:-}" ]]; then
      echo "GITHUB_NAME and PROJECT_REPO must be set."
      exit 1
    fi

    echo "WARNING: This will remove compose containers/volumes and delete ${GITHUB_NAME}/${PROJECT_REPO} on GitHub."
    read -r -p "Type YES to continue: " confirm
    if [[ "$confirm" != "YES" ]]; then
      echo "Aborted."
      exit 1
    fi

    docker compose down --volumes --remove-orphans
    if gh repo view "${GITHUB_NAME}/${PROJECT_REPO}" >/dev/null 2>&1; then
      gh repo delete "${GITHUB_NAME}/${PROJECT_REPO}" --yes
    else
      echo "GitHub repo ${GITHUB_NAME}/${PROJECT_REPO} not found, skipping."
    fi

# Up containers
up:
    docker compose up -d --wait

# Up containers, with build forced
build:
    docker compose up -d --build

# Down containers
down:
    docker compose down
