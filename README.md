# Docker WordPress Boilerplate (Apache, PHP-FPM, MariaDB, WP-CLI, phpMyAdmin)

[![Latest tag](https://img.shields.io/github/v/tag/devgiants/docker-boilerplate-wordpress?sort=semver)](https://github.com/devgiants/docker-boilerplate-wordpress/tags)

A ready-to-start Docker boilerplate for WordPress projects with:
- Apache 2.4 + PHP-FPM
- MariaDB
- WP-CLI
- phpMyAdmin
- Task automation with `just`

## Quick Start

Create a new project from this template:

```bash
composer create-project devgiants/docker-wordpress target-dir
```

Without a version constraint, Composer installs the latest stable release.

If you want `HEAD` of `main`, use:

```bash
composer create-project devgiants/docker-wordpress target-dir dev-main
```

Then go into your project directory and update `.env`.

## Prerequisites

- Docker + Docker Compose plugin (`docker compose` command)
- `just` (task runner)
- `composer` (only needed if you bootstrap with `composer create-project`)
- `envsubst`

### Install `just`

Use your preferred package manager:

```bash
# macOS (Homebrew)
brew install just

# Rust toolchain (cross-platform)
cargo install just

# Ubuntu/Debian (if available in your repos)
sudo apt install just
```

If your distro package is unavailable/outdated, use `cargo install just`.

### Install `envsubst`

On macOS:

```bash
brew install gettext
brew link --force gettext
```

On most Linux distros, `envsubst` is provided by `gettext`.

## Configuration (`.env`)

Set all values before first initialization.

### Directories

- `WORDPRESS_HOST_RELATIVE_APP_PATH`: host path mounted to `/var/www/html` (default `./`)
- `LOGS_DIR`: Apache logs directory on host

### Runtime

- `PHP_VERSION`: PHP version used to build the PHP container
- `MARIADB_VERSION`: MariaDB image tag
- `TIMEZONE`: container timezone

### Host Mapping

- `HOST_USER`: your host username
- `HOST_UID`: your host UID (used for file ownership mapping)
- `HOST_GID`: your host GID

### WordPress

- `PROJECT_NAME`: WordPress site title
- `ADMIN_USER`: initial admin username
- `ADMIN_EMAIL`: initial admin email
- `ADMIN_PASSWORD`: initial admin password (keep quotes if needed)
- `BO_URL`: back-office path slug used for authenticated warmup requests (for example `wp-admin`); set it without leading/trailing slash
- `WP_CLI_CACHE_DIR`: WP-CLI cache path
- `DIVI_USERNAME`: Elegant Themes username (used by `just set-divi-api-key`)
- `DIVI_API_KEY`: Elegant Themes API key (used by `just set-divi-api-key`)
- `THEME_UPDATE_RECHECK_PASSES`: number of HTTP warmup passes before `just update-themes` (default `5`)
- `PLUGIN_UPDATE_RECHECK_PASSES`: number of HTTP warmup passes before `just update-plugins` (default `5`)
- `UPDATE_WARMUP_PASSES`: fallback warmup pass count if specific vars above are not set (default `5`)
- `UPDATE_WARMUP_SLEEP_SECONDS`: delay between warmup passes (default `2`)

### GitHub (used by `just install-and-version`)

- `GITHUB_NAME`: GitHub owner/org
- `PROJECT_REPO`: GitHub repository name

### Database

- `MYSQL_HOST`: DB host (`mysql` by default, must match compose service name)
- `MYSQL_DATABASE`: DB name
- `MYSQL_DATABASE_PREFIX`: WordPress table prefix
- `MYSQL_USER`: DB user
- `MYSQL_PASSWORD`: DB password
- `MYSQL_HOST_PORT`: host port mapped to DB
- `MYSQL_PORT`: DB port inside container (default `3306`)

### Ports

- `APPLICATION_WEB_PORT`: Apache exposed port (default `80`)
- `PHP_MY_ADMIN_PORT`: phpMyAdmin exposed port (default `81`)

## Usage

List available recipes:

```bash
just --list
```

### Initial project setup

```bash
just configure-wordpress
```

This recipe:
- builds/starts containers
- waits for DB readiness
- generates `wp-cli.yml` and `deploy.php` from `.dist` templates
- installs/configures WordPress
- installs a default plugin set

### Day-to-day commands

```bash
just up             # Start containers
just down           # Stop containers
just build          # Rebuild + start containers
just bash-php       # Shell in PHP container as www-data
just bash-php-root  # Shell in PHP container as root
```

### Maintenance commands

```bash
just update-core
just update-plugins
just update-themes
just warmup-updates
just update-translations
just update-all
just search-replace
just set-uploads-permissions
just set-divi-api-key
just erase-all
```

`set-divi-api-key` writes Divi update credentials to the WordPress option `et_automatic_updates_options` using WP-CLI.
`warmup-updates` emulates authenticated back-office page loads (`/${BO_URL}/`) + front-office hits + cron triggers to refresh update metadata (same effect as manual BO/FO navigation).
`update-themes` and `update-plugins` call this warmup automatically before applying updates (`THEME_UPDATE_RECHECK_PASSES` / `PLUGIN_UPDATE_RECHECK_PASSES`).
Core recipes can execute optional hooks when present:
- `update-themes-pre-hook`
- `update-themes-post-hook`
- `update-plugins-pre-hook`
- `update-plugins-post-hook`
`erase-all` is a destructive test helper: it stops/removes the compose stack, removes compose volumes, and deletes `${GITHUB_NAME}/${PROJECT_REPO}` on GitHub. It asks for an inline `YES` confirmation before running.

### Private Just overlays

The root `justfile` can optionally import extra local files:

- `justfile.local`
- `justfile.private`
- `justfile.user`

Role of this feature:
- keep personal/team-specific recipes out of the shared `justfile`
- avoid committing private automation (local credentials, shortcuts, machine-specific tasks)
- extend project commands without changing versioned project files
- inject project-specific update logic (for example Divi/Elegant Themes fallbacks) via the optional hook recipes listed above

These files are ignored by git via `justfile.*`.

Example:

```just
# justfile.private (not committed)
deploy-prod:
    ./scripts/deploy-prod.sh
```

### Repository bootstrap helper

```bash
just install-and-version
```

`install-and-version` assumes you are authenticated with GitHub CLI (`gh auth login`), bootstraps WordPress/GitHub/Git on first run, and skips GitHub bootstrap if the local git repo is already initialized.

## Tools (`tools/`)

The `tools/` directory contains helper scripts that are not part of the main `just` workflow.

### `check_wordpress_state.py`

This script compares a local WordPress instance against production and returns a non-zero exit code only when a blocking mismatch is detected.

What it checks:
- admin login through the hidden back-office slug (`/${BO_URL}/`) and final access to `/wp-admin/`
- page-by-page comparison between production and local URLs
- `<title>` equality
- first `<h1>` equality
- visible text similarity
- HTML similarity after basic normalization (URLs, scripts, styles)

Files:
- `tools/check_wordpress_state.py`: executable Python script
- `tools/check_wordpress_state.example.json`: sample JSON configuration

Recommended workflow:

1. Make sure the local stack is up and the site is reachable.
2. Run the checker in the mode that matches your migration/update context.
3. Review the `SUMMARY` block first, then inspect page-level details only if the summary is `WARN` or `FAIL`.
4. If needed, rerun with explicit paths for the pages that matter most to the project.

Basic usage:

```bash
./tools/check_wordpress_state.py \
  --prod-base https://example.com \
  --local-port 8080 \
  --bo-url hidden-admin-slug \
  --admin-user admin \
  --admin-password 'replace-me' \
  --path / \
  --path /sample-page/
```

Usage with a project `.env`:

```bash
set -a
source .env
set +a
./tools/check_wordpress_state.py --mode visual-ish
```

Usage with a JSON config file:

```bash
cp tools/check_wordpress_state.example.json /tmp/check-wordpress-state.json
$EDITOR /tmp/check-wordpress-state.json
./tools/check_wordpress_state.py --config /tmp/check-wordpress-state.json
```

Configuration sources are resolved in this order: CLI options, JSON config, environment variables, then script defaults.

Supported environment variables:
- `PROD_SITE_URL`
- `LOCAL_BASE_URL`
- `APPLICATION_WEB_PORT`
- `BO_URL`
- `ADMIN_USER`
- `ADMIN_PASSWORD`
- `CHECK_TIMEOUT`
- `CHECK_USER_AGENT`
- `CHECK_MODE`
- `CHECK_MIN_HTML_SIMILARITY`
- `CHECK_MIN_TEXT_SIMILARITY`

Important behavior:
- if `--local-base` is omitted, the script builds `http://localhost:<port>` from `--local-port` or `APPLICATION_WEB_PORT`
- if no paths are provided, it falls back to the hard-coded defaults in the script; these sample paths are project-specific and should usually be overridden
- `strict` mode is the default: HTML similarity is enforced in addition to title/H1/text checks
- `visual-ish` mode ignores low HTML similarity when visible text still matches closely

Recommended modes:
- `strict`: use for classic updates where you expect the DOM to stay close to production
- `visual-ish`: use for builders/framework migrations such as Divi 4 -> Divi 5, where rendered content may stay stable while DOM structure changes heavily

Examples:

```bash
# Strict comparison with explicit thresholds.
./tools/check_wordpress_state.py \
  --config /tmp/check-wordpress-state.json \
  --mode strict \
  --min-html-similarity 0.95 \
  --min-text-similarity 0.98
```

```bash
# Divi 5 / strong DOM drift: prioritize visible text over raw HTML.
./tools/check_wordpress_state.py \
  --config /tmp/check-wordpress-state.json \
  --mode visual-ish \
  --min-text-similarity 0.98
```

Output format:
- `ADMIN_LOGIN`: login URL used, final URL reached, login cookie status, page title
- `PAGE_COMPARE`: one block per checked path with status and similarity metrics
- `SUMMARY`: final status and per-check recap

How to read the metrics:
- `html_similarity`: structure-oriented comparison after removing scripts/styles and normalizing base URLs
- `text_similarity`: visible-text comparison after stripping markup
- low `html_similarity` with high `text_similarity` usually means markup drift, not content drift
- title/H1 mismatches are treated as blocking because they usually indicate a real page-level regression

Status semantics:
- `OK`: page/admin check is within the configured expectations
- `WARN`: content still matches closely enough, but a non-blocking threshold was crossed
- `FAIL`: admin access is broken, HTTP fetch failed, or a blocking mismatch (for example title/H1) was detected

Exit codes:
- `0`: all checks passed, or only non-blocking warnings were found
- `1`: at least one blocking failure was found

## Access URLs

- WordPress: `http://localhost:${APPLICATION_WEB_PORT}` (default `http://localhost`)
- phpMyAdmin: `http://localhost:${PHP_MY_ADMIN_PORT}` (default `http://localhost:81`)

## Reset From Scratch

1. Stop containers:

```bash
docker compose down
```

2. Remove WordPress files and DB data using the paths configured in `.env`.
3. Re-run initialization:

```bash
just configure-wordpress
```

For full test reset (including remote GitHub repo deletion), use:

```bash
just erase-all
```

## Notes

- WP-CLI commands should generally be run as `www-data` inside the PHP container.
- `configure-wordpress` consumes template files (`wp-cli.yml.dist`, `deploy.php.dist`) by generating runtime files and removing `.dist` files.
