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
        admin_paths=("/wp-admin/" "/wp-admin/plugins.php" "/wp-admin/update-core.php")
        ;;
      themes)
        admin_paths=("/wp-admin/" "/wp-admin/themes.php" "/wp-admin/update-core.php")
        ;;
      both)
        admin_paths=("/wp-admin/" "/wp-admin/plugins.php" "/wp-admin/themes.php" "/wp-admin/update-core.php")
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
      --data-urlencode "redirect_to=${app_url}/wp-admin/" \
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

update-plugins: up
    #!/usr/bin/env bash
    set -euo pipefail
    recheck_passes="${PLUGIN_UPDATE_RECHECK_PASSES:-${UPDATE_WARMUP_PASSES:-5}}"
    sleep_seconds="${UPDATE_WARMUP_SLEEP_SECONDS:-2}"
    et_updates=()

    fetch_et_plugin_updates() {
      local php_code
      php_code='define("WP_ADMIN", true);'
      php_code+=$'\n''require "/var/www/html/wp-load.php";'
      php_code+=$'\n''require_once ABSPATH . "wp-admin/includes/plugin.php";'
      php_code+=$'\n''$o = get_site_option("et_automatic_updates_options", []); if (!$o) { $o = get_option("et_automatic_updates_options", []); }'
      php_code+=$'\n''$plugins = []; foreach (get_plugins() as $file => $plugin) { $update_uri = isset($plugin["UpdateURI"]) ? (string) $plugin["UpdateURI"] : ""; if ($update_uri !== "" && strpos($update_uri, "elegantthemes.com") === false) { continue; } $plugins[$file] = (string) $plugin["Version"]; }'
      php_code+=$'\n''$body = ["action" => "check_all_plugins_updates", "installed_plugins" => $plugins, "class_version" => (defined("ET_CORE_VERSION") ? ET_CORE_VERSION : "1.2")];'
      php_code+=$'\n''$user = isset($o["username"]) ? (string) $o["username"] : ""; $key = isset($o["api_key"]) ? (string) $o["api_key"] : "";'
      php_code+=$'\n''if ($user !== "" && $key !== "") { $body["automatic_updates"] = "on"; $body["username"] = urlencode($user); $body["api_key"] = $key; }'
      php_code+=$'\n''$r = wp_remote_post("https://www.elegantthemes.com/api/api.php", ["timeout" => 20, "body" => $body, "headers" => ["rate_limit" => "false"], "user-agent" => "WordPress/" . get_bloginfo("version") . "; Plugin Updates/" . (defined("ET_CORE_VERSION") ? ET_CORE_VERSION : "1.2") . "; " . home_url("/")]);'
      php_code+=$'\n''if (is_wp_error($r)) { echo "ERROR|" . $r->get_error_message(); return; }'
      php_code+=$'\n''if (wp_remote_retrieve_response_code($r) !== 200) { echo "ERROR|HTTP_" . wp_remote_retrieve_response_code($r); return; }'
      php_code+=$'\n''$data = maybe_unserialize(wp_remote_retrieve_body($r)); if (!is_array($data)) { echo "ERROR|invalid_response"; return; }'
      php_code+=$'\n''$updates = [];'
      php_code+=$'\n''foreach ($data as $plugin_file => $plugin_data) {'
      php_code+=$'\n''  if (!is_array($plugin_data) && !is_object($plugin_data)) { continue; }'
      php_code+=$'\n''  $new_version = is_array($plugin_data) ? (isset($plugin_data["new_version"]) ? (string) $plugin_data["new_version"] : "") : (isset($plugin_data->new_version) ? (string) $plugin_data->new_version : "");'
      php_code+=$'\n''  $package = is_array($plugin_data) ? (isset($plugin_data["package"]) ? (string) $plugin_data["package"] : "") : (isset($plugin_data->package) ? (string) $plugin_data->package : "");'
      php_code+=$'\n''  if ($new_version === "" || $package === "") { continue; }'
      php_code+=$'\n''  $installed_version = isset($plugins[$plugin_file]) ? (string) $plugins[$plugin_file] : "";'
      php_code+=$'\n''  if ($installed_version !== "" && version_compare($installed_version, $new_version, ">=")) { continue; }'
      php_code+=$'\n''  $updates[] = [$plugin_file, $installed_version, $new_version, $package];'
      php_code+=$'\n''}'
      php_code+=$'\n''if (empty($updates)) { echo "NO_UPDATE|"; return; }'
      php_code+=$'\n''foreach ($updates as $u) { echo "UPDATE|" . $u[0] . "|" . $u[1] . "|" . $u[2] . "|" . $u[3] . "\n"; }'
      docker compose exec -T -u www-data php php -r "$php_code"
    }

    just warmup-updates plugins "$recheck_passes" "$sleep_seconds"

    et_result="$(fetch_et_plugin_updates || true)"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      status="${line%%|*}"
      rest="${line#*|}"

      if [[ "$status" == "UPDATE" ]]; then
        IFS='|' read -r plugin_file installed_version target_version package_url <<< "${rest}"
        echo "ET API plugin update detected: ${plugin_file} (${installed_version} -> ${target_version})"
        et_updates+=("${plugin_file}|${target_version}|${package_url}")
      elif [[ "$status" == "ERROR" ]]; then
        echo "ET API plugin check error: ${rest}"
      fi
    done <<< "$et_result"

    if (( ${#et_updates[@]} > 0 )); then
      for item in "${et_updates[@]}"; do
        IFS='|' read -r plugin_file target_version package_url <<< "$item"
        echo "Installing ET plugin package for ${plugin_file} (${target_version})..."
        docker compose exec -T -u www-data php wp plugin install "$package_url" --force
      done
    fi

    echo "Plugins with updates currently visible to WordPress:"
    docker compose exec -T -u www-data php wp plugin list --update=available || true

    docker compose exec -u www-data php wp plugin update --all --exclude=backwpup

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
    et_divi_package_url=""
    et_divi_target_version=""

    fetch_divi_update_info() {
      local php_code
      php_code='define("WP_ADMIN", true);'
      php_code+=$'\n''require "/var/www/html/wp-load.php";'
      php_code+=$'\n''$o = get_site_option("et_automatic_updates_options", []); if (!$o) { $o = get_option("et_automatic_updates_options", []); }'
      php_code+=$'\n''$themes = wp_get_themes(); $installed = []; foreach ($themes as $slug => $theme) { $installed[$slug] = (string) $theme->get("Version"); }'
      php_code+=$'\n''$body = ["action" => "check_theme_updates", "installed_themes" => $installed, "class_version" => (defined("ET_CORE_VERSION") ? ET_CORE_VERSION : "1.0")];'
      php_code+=$'\n''$user = isset($o["username"]) ? (string) $o["username"] : ""; $key = isset($o["api_key"]) ? (string) $o["api_key"] : "";'
      php_code+=$'\n''if ($user !== "" && $key !== "") { $body["automatic_updates"] = "on"; $body["username"] = urlencode($user); $body["api_key"] = $key; }'
      php_code+=$'\n''$r = wp_remote_post("https://www.elegantthemes.com/api/api.php", ["timeout" => 20, "body" => $body, "headers" => ["rate_limit" => "false"], "user-agent" => "WordPress/" . get_bloginfo("version") . "; Theme Updates/" . (defined("ET_CORE_VERSION") ? ET_CORE_VERSION : "1.0") . "; " . home_url("/")]);'
      php_code+=$'\n''if (is_wp_error($r)) { echo "ERROR|" . $r->get_error_message(); return; }'
      php_code+=$'\n''if (wp_remote_retrieve_response_code($r) !== 200) { echo "ERROR|HTTP_" . wp_remote_retrieve_response_code($r); return; }'
      php_code+=$'\n''$data = maybe_unserialize(wp_remote_retrieve_body($r));'
      php_code+=$'\n''if (!is_array($data) || empty($data["Divi"])) { echo "NO_UPDATE|"; return; }'
      php_code+=$'\n''$divi = $data["Divi"]; $new = isset($divi["new_version"]) ? (string) $divi["new_version"] : ""; $pkg = isset($divi["package"]) ? (string) $divi["package"] : "";'
      php_code+=$'\n''if ($new === "" || $pkg === "") { echo "NO_UPDATE|"; return; }'
      php_code+=$'\n''$installed = isset($installed["Divi"]) ? (string) $installed["Divi"] : "";'
      php_code+=$'\n''if ($installed !== "" && version_compare($installed, $new, ">=")) { echo "NO_UPDATE|"; return; }'
      php_code+=$'\n''echo "UPDATE|" . $new . "|" . $pkg;'
      docker compose exec -T -u www-data php php -r "$php_code"
    }

    divi_version="$(docker compose exec -T -u www-data php wp theme get Divi --field=version 2>/dev/null || true)"
    if [[ -n "$divi_version" ]]; then
      echo "Divi current version: $divi_version"
    else
      echo "Divi theme not found."
    fi

    just warmup-updates themes "$recheck_passes" "$sleep_seconds"

    et_result="$(fetch_divi_update_info || true)"
    et_status="${et_result%%|*}"
    et_rest="${et_result#*|}"
    if [[ "$et_status" == "UPDATE" ]]; then
      et_divi_target_version="${et_rest%%|*}"
      et_divi_package_url="${et_rest#*|}"
      echo "ET API Divi update detected: ${et_divi_target_version}"
      docker compose exec -T -u www-data php wp theme install "$et_divi_package_url" --force
    elif [[ "$et_status" == "ERROR" ]]; then
      echo "ET API Divi check error: ${et_rest}"
    fi

    echo "Themes with updates currently visible to WordPress:"
    docker compose exec -T -u www-data php wp theme list --update=available || true

    docker compose exec -u www-data php wp theme update --all

    updated_divi_version="$(docker compose exec -T -u www-data php wp theme get Divi --field=version 2>/dev/null || true)"
    if [[ -n "$updated_divi_version" ]]; then
      echo "Divi version after update: $updated_divi_version"
    fi

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
