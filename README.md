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
- `WP_CLI_CACHE_DIR`: WP-CLI cache path

### GitHub (used by `just install-complete`)

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
just update-translations
just update-all
just search-replace
just set_uploads_permissions
```

### Repository bootstrap helper

```bash
just install-complete
```

`install-complete` assumes you are authenticated with GitHub CLI (`gh auth login`) and rewrites local git history/remote setup for the target repo.

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

## Notes

- WP-CLI commands should generally be run as `www-data` inside the PHP container.
- `configure-wordpress` consumes template files (`wp-cli.yml.dist`, `deploy.php.dist`) by generating runtime files and removing `.dist` files.
