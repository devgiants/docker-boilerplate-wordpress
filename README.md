# Ready-To-Start LAMP stack with Wordpress, WP-CLI and PHPMyAdmin
This boilerplate is a ready-to-start customizable LAMP stack with Wordpress, WP-CLI and PHPMyAdmin integration. 
__Warning : for Linux users only__.

## Installation
So far, just __download archive__ and __extract it__ in the __target project directory__ (i.e `/home/your_user/my_project`).

## Configuration
### Custom parameters

#### .env file
First of all, specify parameters needed for the project

##### Directories
- __WORDPRESS_HOST_RELATIVE_APP_PATH__: This is the relative path from project initial path. Default to `./symfony`. _Note: a volume will be created on this path in order to persist Wordpress app files_. 
- __LOGS_DIR__: The logs directory.

##### Host
- __HOST_UID__: Your current user host ID (uid). This is mandatory to map the UID between PHP container and host, in order to let you edit files both in container an through host volume access.
- __HOST_GID__: Your current main group host ID (gid). (Not used so far)

##### Wordpress
- __PROJECT_NAME__: The project name : used as Wordpress site name
- __ADMIN_USER__:

##### Database
- __MYSQL_HOST__: The database host. Has to be equal to database container name in `docker-compose.yml` file (default `mysql`).    
- __MYSQL_DB__: The database name you want
- __MYSQL_USER__: root (not used so far, assuming root connection on dev stage)
- __MYSQL_ROOT_PASSWORD__: the database password you want 
- __MYSQL_PORT__: the MySQL instance port. Careful, this is the MySQL port __in container__. Default to `3306`  
- __MYSQL_HOST_VOLUME_PATH__: default `./docker/mysql/5.7`. This is the volume which will store database.

##### Ports    

You can have multiple projects using this boilerplate, but without changing ports, only one project can be up at a time, because port 80 is used to expose Apache.

- __APPLICATION_WEB_PORT__: default to `80`.
- __PHP_MY_ADMIN_PORT__: default to `81`.


## Usage
There are 2 ways to use this : __initialisation__ and __day-to-day usage__.
### Initialisation
You have to run `bash init.sh`. This script will :
1. Make system live (creates/update and run containers).
2. Download latest WP core on fr_FR locale (using `wp-cli.yml` file).
3. Setup the system by creating `wp-config.php` (using `wp-cli.yml` file).
4. Create database (using `wp-cli.yml` file).
5. Install WP and creates user (using `wp-cli.yml` file).
6. Loop on `plugins.txt` file to install plugins
  - _Note: use the plugin slug if you want to add one to list. The slug is the last part of the official Worpdress plugin URL_
7. Clean tedious elements (page and post example)
8. Setup permalinks to `%postname%` and regenerate `.htaccess`
 

### Day-to-day usage
Then, on day-to-day usage, just run 
- `docker-compose up` to make system live
- `docker-compose stop` to shutdown this project without removing containers. 

_Note : Once you have stop one project, you can up another one safely._

_Note : All volumes set will ensure to persist both app files and database._

### Symfony
Accessible on `localhost` by default.

Important note : to execute wp-cli, __be sure to connect to php container with www-data user__. The mapping described above targets www-data on container.
Command to use : `docker-compose exec -u www-data php wp your_command`

### PhpMyAdmin
Accessible on `localhost:81` by default. Use `MYSQL_USER` and `MYSQL_ROOT_PASSWORD` to connect.