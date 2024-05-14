# Ready-To-Start LAMP stack with Wordpress, WP-CLI and PHPMyAdmin
This boilerplate is a ready-to-start customizable LAMP stack with Wordpress, WP-CLI and PHPMyAdmin integration. 
__Warning : for Linux users only__.

## Installation
Use composer `create-project` command :

```
composer create-project devgiants/docker-wordpress target-dir 1.6.6
```

This will clone the stack in your directory

### Requirements

**Mac users** : During installation, the script requires the use of envsubst which is not installed by default on MacOS. You can install it directly with Homebrew:

```
brew install gettext
brew link --force gettext 
```

## Configuration
### Custom parameters

#### .env file
First of all, specify parameters needed for the project

##### Directories
- __WORDPRESS_HOST_RELATIVE_APP_PATH__: This is the relative path from project initial path. Default to `./`. _Note: a volume will be created on this path in order to persist Wordpress app files_. 
- __LOGS_DIR__: The logs directory.

##### PHP
- __PHP_VERSION__: the PHP version to use for stack

##### Host
- __HOST_USER__: Your current username. Needed to ensure creation (directories...) with your current user to preserve mapping between container and host
- __HOST_UID__: Your current user host ID (uid). This is mandatory to map the UID between PHP container and host, in order to let you edit files both in container an through host volume access.
- __HOST_GID__: Your current main group host ID (gid). (Not used so far)

##### Wordpress
- __PROJECT_NAME__: The project name : used as Wordpress site name. __IMPORTANT : as this is used for setting the theme directory as well, keep this name with underscores (i.e : project_test)__
- __ADMIN_USER__: the first user to be created
- __ADMIN_PASSWORD__: the first user password. __IMPORTANT: Keep it enclosed with double quotes__.
- __PROJECT_REPO__: the git repo address

- __WP_CLI_CACHE_DIR__: WP-CLI cache directory. Leave it this way.

##### Database
- __MYSQL_HOST__: The database host. Has to be equal to database container name in `docker-compose.yml` file (default `mysql`).    
- __MYSQL_DATABASE__: The database name you want
- __MYSQL_DATABASE_PREFIX__: THe database prefix you want for your Wordpress installation
- __MYSQL_USER__: THe database user you want to use (will be created on container creation)
- __MYSQL_PASSWORD__: the database password you want 
- __MYSQL_HOST_PORT__: the host port you want to bind Mysql Server in container to. 
- __MYSQL_PORT__: the MySQL instance port. Careful, this is the MySQL port __in container__. Default to `3306`  
- __MYSQL_HOST_VOLUME_PATH__: default `./docker/data/mysql/5.7`. This is the volume which will store database.

##### Ports    

You can have multiple projects using this boilerplate, but without changing ports, only one project can be up at a time, because port 80 is used to expose Apache.

- __APPLICATION_WEB_PORT__: default to `80`.
- __PHP_MY_ADMIN_PORT__: default to `81`.


## Usage
There are 2 ways to use this : __initialisation__ and __day-to-day usage__. A `Makefile` is created to help manipulate things
### Initialisation

#### Blank project
Just execute `make install` to completly setup blank project. Please look to other entry points in `Makefile` to see what you can do

#### Project with Sage 9 theme

Just execute `make sage` to set a complete project with Sage 9.

### Day-to-day usage

- Execute `make up` for bringing project live
- Execute `make down` for stopping and removing container instances.
- Execute `make bash-php` for a shell in PHP container with `www-data` user.


_Note : All volumes set will ensure to persist both app files and database._

### Reset from scratch
If you want to reset everything, just
1. Run `docker-compose down`.
2. Remove the __WORDPRESS_HOST_RELATIVE_APP_PATH__ and the __MYSQL_HOST_VOLUME_PATH__.
3. Then goes back on `make install`.

### Wordpress
Accessible on `localhost` by default.

Important note : to execute wp-cli, __be sure to connect to php container with www-data user__. The mapping described above targets www-data on container.
Command to use : `make bash-php`

### PhpMyAdmin
Accessible on `localhost:81` by default. Use `MYSQL_USER` and `MYSQL_PASSWORD` to connect.
