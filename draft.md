# Dockerizing Django with Postgres, Uvicorn, and Traefik

In this tutorial, we look at how to set up Django with Postgres, Uvicorn, and Docker. For production environments, we'll add on Gunicorn, Traefik, and Let's Encrypt.

## Project Setup

Start by creating a project directory:

```sh
$ mkdir django-docker-traefik && cd django-docker-traefik
$ python3.9 -m venv venv
$ source venv/bin/activate
```

> Feel free to swap out virtualenv and Pip for [Poetry](https://python-poetry.org/) or [Pipenv](https://pipenv.pypa.io/). For more, review [Modern Python Environments](/blog/python-environments/).

Add [Django](https://www.djangoproject.com/) to *requirements.txt*:

```
Django==3.2.3
```

Install them:

```sh
(venv)$ pip install -r requirements.txt
```

Next, let's create a simple Django application:

```bash
(venv)$ django-admin startproject config .
(venv)$ python manage.py migrate
```

Run the application:

```sh
(venv)$ python manage.py runserver
```

Navigate to [127.0.0.1:8000](http://127.0.0.1:8000). You should see the django welcome page.

Kill the server once done.

## Docker

Install [Docker](https://docs.docker.com/install/), if you don't already have it, then add a *Dockerfile* to the project root:

```Dockerfile
# Dockerfile

# pull the official docker image
FROM python:3.9.5-slim

# set work directory
WORKDIR /app

# set env variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# copy project
COPY . .
```

So, we started with a `slim` [Docker image](https://hub.docker.com/_/python/) for Python 3.9.4. We then set up a [working directory](https://docs.docker.com/engine/reference/builder/#workdir) along with two environment variables:

1. `PYTHONDONTWRITEBYTECODE`: Prevents Python from writing pyc files to disc (equivalent to `python -B` [option](https://docs.python.org/3/using/cmdline.html#id1))
1. `PYTHONUNBUFFERED`: Prevents Python from buffering stdout and stderr (equivalent to `python -u` [option](https://docs.python.org/3/using/cmdline.html#cmdoption-u))

Finally, we copied over the *requirements.txt* file, installed the dependencies, and copied over the project.

> Review [Docker for Python Developers](https://mherman.org/presentations/dockercon-2018) for more on structuring Dockerfiles as well as some best practices for configuring Docker for Python-based development.

Next, add a *docker-compose.yml* file to the project root:

```yaml
# docker-compose.yml

version: '3.8'

services:
  web:
    build: .
    command: python /app/manage.py runserver 0.0.0.0:8000
    volumes:
      - .:/app
    ports:
      - 8008:8000
```

> Review the [Compose file reference](https://docs.docker.com/compose/compose-file/) for info on how this file works.

Build the image:

```sh
$ docker-compose build
```

Once the image is built, run the container:

```sh
$ docker-compose up -d
```

Navigate to [http://localhost:8008](http://localhost:8008) to again view the welcome page.

> Check for errors in the logs if this doesn't work via `docker-compose logs -f`.

## Postgres

To configure Postgres, we need to add a new service to the *docker-compose.yml* file, set up an ORM, and install [asyncpg](https://github.com/MagicStack/asyncpg).

First, add a new service called `db` to *docker-compose.yml*:

```yaml
# docker-compose.yml

version: '3.8'

services:
  web:
    build: .
    command: bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; command: python /app/manage.py runserver 0.0.0.0:8000'
    volumes:
      - .:/app
    ports:
      - 8008:8000
    environment:
      - DATABASE_URL=postgresql://django_traefik:django_traefik@db:5432/django_traefik
    depends_on:
      - db
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=django_traefik
      - POSTGRES_PASSWORD=django_traefik
      - POSTGRES_DB=django_traefik

volumes:
  postgres_data:
```

To persist the data beyond the life of the container we configured a volume. This config will bind `postgres_data` to the "/var/lib/postgresql/data/" directory in the container.

We also added an environment key to define a name for the default database and set a username and password.

> Review the "Environment Variables" section of the [Postgres Docker Hub page](https://hub.docker.com/_/postgres) for more info.

Take note of the new command in the `web` service:

```sh
bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; python /app/manage.py runserver 0.0.0.0:8000'
```

`while !</dev/tcp/db/5432; do sleep 1` will continue until Postgres is up. Once up, `python /app/manage.py runserver 0.0.0.0:8000` runs.

Let's setup the django postgres connection, add [django-environ](https://django-environ.readthedocs.io/en/latest/), to load/read environment variables and [psycopg2](https://github.com/psycopg/psycopg2), a postgres driver for python:

```text
django-environ==0.4.5
psycopg2-binary==2.8.6
```

```python
# config/settings.py

# read the environment variables
import environ
env = environ.Env()

# setup the connection
DATABASES = {
    "default": env.db(),
}
```

Django-environ automatically parses the database connection url strings like `psql://user:pass@127.0.0.1:8458/db`.

Next, we will create a new [django-admin command](https://docs.djangoproject.com/en/3.2/howto/custom-management-commands/) to create a dummy entry into our database. 

Create a new app:

```bash
(venv)$ python manage.py startapp users
```

Add the newly created app to `INSTALLED_APPS`:

```python
# config/settings.py

INSTALLED_APPS = [
    ...
    "users",
]
```

Create a new file, `users/management/commands/create_user.py`, maintaining the following structure.

```bash
users
├── __init__.py
├── admin.py
├── apps.py
├── management
│   ├── __init__.py
│   └── commands
│       ├── __init__.py
│       └── create_user.py
├── migrations
│   └── __init__.py
├── models.py
├── tests.py
└── views.py
```

```python
# users/management/commands/create_user.py

from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from typing import Any, Optional


class Command(BaseCommand):
    def handle(self, *args: Any, **options: Any) -> Optional[str]:
        User.objects.get_or_create(email="test@test.com")
        self.stdout.write(self.style.SUCCESS("User added"))
```

```python
User.objects.get_or_create(email="test@test.com")
```

The above line in the handle function adds a dummy entry to our table once we issue the command `python manage.py create_user`. `get_or_create` makes sure that the entry is created only if it doesn't already exist.

Build the new image and spin up the two containers:

```sh
$ docker-compose up -d --build
```

Run the initial migration:
```bash
$ docker-compose exec web python /app/manage.py migrate
```

Create the dummy entry:
```bash
$ docker-compose exec web python /app/manage.py create_user
User added
```

The `User` model is the default model for representing a user, provided by the django-admin. The associated table(`auth_user`) and fields are created upon initial migration.

You can check that the volume was created by running:

```sh
$ docker volume inspect django-docker-traefik_postgres_data
```

You should see something similar to:

```sh
[
    {
        "CreatedAt": "2021-05-17T09:14:44Z",
        "Driver": "local",
        "Labels": {
            "com.docker.compose.project": "django-docker-traefik",
            "com.docker.compose.version": "1.29.1",
            "com.docker.compose.volume": "postgres_data"
        },
        "Mountpoint": "/var/lib/docker/volumes/django-docker-traefik_postgres_data/_data",
        "Name": "django-docker-traefik_postgres_data",
        "Options": null,
        "Scope": "local"
    }
]
```

Next, create a new file, `entrypoint.sh` to do the following:
1. Wait for the postgres connection.
1. Create the initial migration.
1. Create the dummy user.

```bash
#!/bin/sh

echo "Waiting for postgres..."

while ! nc -z db 5432; do
    sleep 0.1
done

echo "PostgreSQL started"

python $APP_HOME/manage.py migrate
python $APP_HOME/manage.py create_user

exec "$@"
```

The value for `$APP_HOME` will be set in the Dockerfile.

Update the file permissions locally:
```bash
chmod +x entrypoint.sh
```

Then, update the Dockerfile to install [Netcat](http://netcat.sourceforge.net/), copy over the entrypoint.sh file, and run the file as the Docker [entrypoint](https://docs.docker.com/engine/reference/builder/#entrypoint) command:

```dockerfile
# pull the official docker image
FROM python:3.9.5-slim

# set app path
ENV APP_HOME=/app

# set work directory
WORKDIR ${APP_HOME}

# set env variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install system dependencies
RUN apt-get update && apt-get install -y netcat

# install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt

# copy project
COPY . .


ENTRYPOINT ["/app/entrypoint.sh"]
```

Finally, modify the command for the `web` service in _docker-compose.yml_ file.

```yaml
command: python /app/manage.py runserver 0.0.0.0:8000
```

Test it out again:
1. Re-build the images
1. Run the containers
1. Try [http://127.0.0.1:8008](http://127.0.0.1:8008)

Checkout the database entry:
```bash
$ docker-compose exec db psql --username=django_traefik --dbname=django_traefik

psql (13.3)
Type "help" for help.

django_traefik=# \c django_traefik
You are now connected to database "django_traefik" as user "django_traefik".
django_traefik=# select * from auth_user;
 id | password | last_login | is_superuser | username | first_name | last_name |     email     | is_staff | is_active |          date_joined
----+----------+------------+--------------+----------+------------+-----------+---------------+----------+-----------+-------------------------------
  1 |          |            | f            |          |            |           | test@test.com | f        | t         | 2021-05-17 09:27:29.131359+00
(1 row)

django_traefik=# \q
```

## Gunicorn

Moving along, for production environments, let's add [Gunicorn](https://gunicorn.org/), a production-grade WSGI server, to the requirements file:

```text
gunicorn==20.1.0
```

Since we still want to use Django's built-in server in development, create a new compose file called _docker-compose.prod.yml_ for production:

```yaml
# docker-compose.prod.yml

version: '3.8'

services:
  web:
    build: .
    command: gunicorn --bind 0.0.0.0:8000 config.wsgi
    ports:
      - 8008:8000
    env_file:
      - ./.env.prod
    depends_on:
      - db
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data_prod:/var/lib/postgresql/data/
    env_file:
      - ./.env.prod.db

volumes:
  postgres_data_prod:
```

> If you have multiple environments, you may want to look at using a [docker-compose.override.yml](https://docs.docker.com/compose/extends/) configuration file. With this approach, you'd add your base config to a docker-compose.yml file and then use a docker-compose.override.yml file to override those config settings based on the environment.

Take note of the default `command`. We're running Gunicorn rather than the Flask development server. We also removed the volume from the `web` service since we don't need it in production. Finally, we're using [separate environment variable files](https://docs.docker.com/compose/env-file/) to define environment variables for both services that will be passed to the container at runtime.

_.env.prod_:

```text
DATABASE_URL=postgresql://django_traefik:django_traefik@db:5432/django_traefik
```

_.env.prod.db_:
```text
POSTGRES_USER=django_traefik
POSTGRES_PASSWORD=django_traefik
POSTGRES_DB=django_traefik
```

Add the two files to the project root. You'll probably want to keep them out of version control, so add them to a _.gitignore_ file.

Bring [down](https://docs.docker.com/compose/reference/down/) the development containers (and the associated volumes with the -v flag):

```bash
$ docker-compose down -v
```

Then, build the production images and spin up the containers:

```bash
$ docker-compose -f docker-compose.prod.yml up -d --build
```

Verify the dummy entry is created. Test out [http://127.0.0.1:8008](http://127.0.0.1:8008)

> If the container fails to start, check for errors in the logs via `docker-compose -f docker-compose.prod.yml logs -f`.

## Production Dockerfile

Create a new Dockerfile called *Dockerfile.prod* for use with production builds:

```Dockerfile
# Dockerfile.prod

###########
# BUILDER #
###########

# pull official base image
FROM python:3.9.5-slim as builder

# set work directory
WORKDIR /app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc

# lint
RUN pip install --upgrade pip
RUN pip install flake8==3.9.1
COPY . .
RUN flake8 --ignore=E501,F401 .

# install python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /usr/src/app/wheels -r requirements.txt


#########
# FINAL #
#########

# pull official base image
FROM python:3.9.5-slim

# create directory for the app user
RUN mkdir -p /home/app

# create the app user
RUN addgroup --system app && adduser --system --group app

# create the appropriate directories
ENV HOME=/home/app
ENV APP_HOME=/home/app/web
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

# install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends netcat
COPY --from=builder /usr/src/app/wheels /wheels
COPY --from=builder /app/requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache /wheels/*

# copy entrypoint.sh
COPY ./entrypoint.sh $APP_HOME

# copy project
COPY . $APP_HOME

# chown all the files to the app user
RUN chown -R app:app $APP_HOME

# change to the app user
USER app

# run entrypoint.prod.sh
ENTRYPOINT ["/home/app/web/entrypoint.sh"]
```

Here, we used a Docker [multi-stage build](https://docs.docker.com/develop/develop-images/multistage-build/) to reduce the final image size. Essentially, `builder` is a temporary image that's used for building the Python wheels. The wheels are then copied over to the final production image and the `builder` image is discarded.

> You could take the [multi-stage build approach](https://stackoverflow.com/a/53101932/1799408) a step further and use a single Dockerfile instead of creating two Dockerfiles. Think of the pros and cons of using this approach over two different files.

Did you notice that we created a non-root user? By default, Docker runs container processes as root inside of a container. This is a bad practice since attackers can gain root access to the Docker host if they manage to break out of the container. If you're root in the container, you'll be root on the host.

Update the web service within the _docker-compose.prod.yml_ file to build with Dockerfile.prod:

```yaml
web:
  build: 
    context: .
    dockerfile: Dockerfile.prod
  command: gunicorn --bind 0.0.0.0:8000 config.wsgi
  ports:
    - 8008:8000
  env_file:
    - ./.env.prod
  depends_on:
    - db
```

Try it out:

```bash
$ docker-compose -f docker-compose.prod.yml down -v
$ docker-compose -f docker-compose.prod.yml up -d --build
```

## Traefik

Next, let's add [Traefik](https://traefik.io/traefik/), a [reverse proxy](https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/), into the mix.

> New to Traefik? Check out the offical [Getting Started](https://doc.traefik.io/traefik/getting-started/concepts/) guide.


> **Traefik vs Nginx**: Traefik is a modern, HTTP reverse proxy and load balancer. It's often compared to [Nginx](https://www.nginx.com/), a web server and reverse proxy. Since Nginx is primarily a webserver, it can be used to serve up a webpage as well as serve as a reverse proxy and load balancer. In general, Traefik is simpler to get up and running while Nginx is more versatile.

>
> **Traefik**:
>
  1. Reverse proxy and load balancer
  1. Automatically issues and renews SSL certificates, via [Let's Encrypt](https://letsencrypt.org/), out-of-the-box
  1. Use Traefik for simple, Docker-based microservices
>
>
> **Nginx**:
>
  1. Web server, reverse proxy, and load balancer
  1. Slightly [faster](https://doc.traefik.io/traefik/v1.4/benchmarks/) than Traefik
  1. Use Nginx for complex services

Add a new file called *traefik.dev.toml*:

```toml
# traefik.dev.toml

# listen on port 80
[entryPoints]
  [entryPoints.web]
    address = ":80"

# Traefik dashboard over http
[api]
insecure = true

[log]
level = "DEBUG"

[accessLog]

# containers are not discovered automatically
[providers]
  [providers.docker]
    exposedByDefault = false
```


Here, since we don't want to expose the `db` service, we set [exposedByDefault](https://doc.traefik.io/traefik/providers/docker/#exposedbydefault) to `false`. To manually expose a service we can add the `"traefik.enable=true"` label to the Docker Compose file.

Next, update the *docker-compose.yml* file so that our `web` service is discovered by Traefik and add a new `traefik` service:

```yaml
# docker-compose.yml

version: '3.8'

services:
  web:
    build: .
    command: python /app/manage.py runserver 0.0.0.0:8000
    volumes:
      - .:/app
    expose: 
      - 8000
    environment:
      - DATABASE_URL=postgresql://django_traefik:django_traefik@db:5432/django_traefik
    depends_on:
      - db
    labels: # new
      - "traefik.enable=true"
      - "traefik.http.routers.django.rule=Host(`django.localhost`)"
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=django_traefik
      - POSTGRES_PASSWORD=django_traefik
      - POSTGRES_DB=django_traefik
  traefik: # new
    image: traefik:v2.2
    ports:
      - 8008:80
      - 8081:8080
    volumes:
      - "$PWD/traefik.dev.toml:/etc/traefik/traefik.toml"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

volumes:
  postgres_data:
```

First, the `web` service is only exposed to other containers on port `8000`. We also added the following labels to the `web` service:

1. `traefik.enable=true` enables Traefik to discover the service
1. ``traefik.http.routers.django.rule=Host(`django.localhost`)`` when the request has `Host=django.localhost`, the request is redirected to this service

Take note of the volumes within the `traefik` service:

1. `./traefik.dev.toml:/etc/traefik/traefik.toml` maps the local config file to the config file in the container so that the settings are kept in sync
1. `/var/run/docker.sock:/var/run/docker.sock:ro` enables traefik to discover other containers

To test, first bring down any existing containers:

```sh
$ docker-compose down -v
$ docker-compose -f docker-compose.prod.yml down -v
```

Build the new development images and spin up the containers:

```sh
$ docker-compose up -d --build
```

Navigate to [http://django.localhost:8008/](http://django.localhost:8008/). You should see the welcome page:


Next, check out the [dashboard](https://doc.traefik.io/traefik/operations/dashboard/) at [django.localhost:8081](http://django.localhost:8081):

<img data-src="/static/images/blog/fastapi-docker-traefik/traefik_dashboard.png"  loading="lazy" class="lazyload" style="max-width:100%" alt="traefik dashboard">

Bring the containers and volumes down once done:

```sh
$ docker-compose down -v
```

## Let's Encrypt

We've successfully created a working example of Fastapi, Docker, and Traefik in development mode. For production, you'll want to configure Traefik to [manage TLS certificates via Let's Encrypt](https://doc.traefik.io/traefik/https/acme/). In short, Traefik will automatically contact the certificate authority to issue and renew certificates.

Since Let's Encrypt won't issue certificates for `localhost`, you'll need to spin up your production containers on a cloud compute instance (like a [DigitalOcean](https://m.do.co/c/d8f211a4b4c2) droplet or an AWS EC2 instance). You'll also need a valid domain name. If you don't have one, you can create a free domain at [Freenom](https://www.freenom.com/).

> We used a [DigitalOcean](https://m.do.co/c/d8f211a4b4c2) droplet along with Docker machine to quickly provision a compute instance with Docker and deployed the production containers to test out the Traefik config. Check out [DigitalOcean example](https://docs.docker.com/machine/examples/ocean/) from the Docker docs for more on using Docker Machine to provision a droplet.

Assuming you configured a compute instance and set up a free domain, you're now ready to set up Traefik in production mode.

Start by adding a production version of the Traefik config to a file called *traefik.prod.toml*:

```toml
# traefik.prod.toml

[entryPoints]
  [entryPoints.web]
    address = ":80"
  [entryPoints.web.http]
    [entryPoints.web.http.redirections]
      [entryPoints.web.http.redirections.entryPoint]
        to = "websecure"
        scheme = "https"

  [entryPoints.websecure]
    address = ":443"

[accessLog]

[api]
dashboard = true

[providers]
  [providers.docker]
    exposedByDefault = false

[certificatesResolvers.letsencrypt.acme]
  email = "your@email.com"
  storage = "/certificates/acme.json"
  [certificatesResolvers.letsencrypt.acme.httpChallenge]
    entryPoint = "web"
```

> Make sure to replace `your@email.com` with your actual email address.

What's happening here:

1. `entryPoints.web` sets the entry point for our insecure HTTP application to port 80
1. `entryPoints.websecure` sets the entry point for our secure HTTPS application to port 443
1. `entryPoints.web.http.redirections.entryPoint` redirects all insecure requests to the secure port
1. `exposedByDefault = false` unexposes all services
1. `dashboard = true` enables the monitoring dashboard

Finally, take note of:

```toml
[certificatesResolvers.letsencrypt.acme]
  email = "your@email.com"
  storage = "/certificates/acme.json"
  [certificatesResolvers.letsencrypt.acme.httpChallenge]
    entryPoint = "web"
```

This is where the Let's Encrypt config lives. We defined where the certificates will be [stored](https://doc.traefik.io/traefik/https/acme/#storage) along with the [verification type](https://doc.traefik.io/traefik/https/acme/#the-different-acme-challenges), which is an [HTTP Challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge).

Next, assuming you updated your domain name's DNS records, create two new A records that both point at your compute instance's public IP:

1. `fastapi-traefik.your-domain.com` - for the web service
1. `dashboard-fastapi-traefik.your-domain.com` - for the Traefik dashboard

> Make sure to replace `your-domain.com` with your actual domain.

Next, update *docker-compose.prod.yml* like so:

```yaml
# docker-compose.prod.yml

version: '3.8'

services:
  web:
    build: 
      context: .
      dockerfile: Dockerfile.prod
    command: gunicorn --bind 0.0.0.0:80 config.wsgi
    expose:  # new
      - 80
    env_file:
      - ./.env.prod
    depends_on:
      - db
    labels:  # new
      - "traefik.enable=true"
      - "traefik.http.routers.django.rule=Host(`django-traefik.yourdomain.com`)"
      - "traefik.http.routers.django.tls=true"
      - "traefik.http.routers.django.tls.certresolver=letsencrypt"
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data_prod:/var/lib/postgresql/data/
    env_file:
      - ./.env.prod.db
  treafik:
    build: 
      context: .
      dockerfile: Dockerfile.traefik
    ports: 
      - 80:80
      - 443:443
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./traefik-public-certificates:/certificates"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`dashboard-django-traefik.yourdomain.com`) && (PathPrefix(`/`)"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=testuser:$$apr1$$jIKW.bdS$$eKXe4Lxjgy/rH65wP1iQe1"
  

volumes:
  postgres_data_prod:
  traefik-public-certificates:
```

> Again, make sure to replace `your-domain.com` with your actual domain.

What's new here?

In the `web` service, we added the following labels:

1. ``traefik.http.routers.django.rule=Host(`django-traefik.yourdomain.com`)`` changes the host to the actual domain
1. `traefik.http.routers.django.tls=true` enables HTTPS
1. `traefik.http.routers.django.tls.certresolver=letsencrypt` sets the certificate issuer as Let's Encrypt

Next, for the `traefik` service, we added the appropriate ports and a volume for the certificates directory. The volume ensures that the certificates persist even if the container is brought down.

As for the labels:

1. ``traefik.http.routers.dashboard.rule=Host(`dashboard-django-traefik.yourdomain.com`)`` defines the dashboard host, so it can can be accessed at `$Host/dashboard/`
1. `traefik.http.routers.dashboard.tls=true` enables HTTPS
1. `traefik.http.routers.dashboard.tls.certresolver=letsencrypt` sets the certificate resolver to Let's Encrypt
1. `traefik.http.routers.dashboard.middlewares=auth` enables `HTTP BasicAuth` middleware
1. `traefik.http.middlewares.auth.basicauth.users` defines the username and hashed password for logging in

You can create a new password hash using the htpasswd utility:

```sh
# username: testuser
# password: password

$ echo $(htpasswd -nb testuser password) | sed -e s/\\$/\\$\\$/g
testuser:$$apr1$$jIKW.bdS$$eKXe4Lxjgy/rH65wP1iQe1
```

Feel free to use an `env_file` to store the username and password as environment variables

```
USERNAME=testiser
HASHED_PASSWORD=$$apr1$$jIKW.bdS$$eKXe4Lxjgy/rH65wP1iQe1
```

Finally, add a new Dockerfile called *Dockerfile.traefik*:

```Dockerfile
# Dockerfile.traefik

FROM traefik:v2.2

COPY ./traefik.prod.toml ./etc/traefik/traefik.toml
```

Next, spin up the new container:

```sh
$ docker-compose -f docker-compose.prod.yml up -d --build
```

Ensure the two URLs work:

1. [https://django-traefik.youdomain.com](https://django-traefik.youdomain.com)
1. [https://dashboard-django-traefik.youdomain.com/dashboard](https://dashboard-django-traefik.youdomain.com/dashboard)

Also, make sure that when you access the HTTP versions of the above URLs, you're redirected to the HTTPS versions.

Finally, Let's Encrypt certificates have a validity of [90 days](https://letsencrypt.org/2015/11/09/why-90-days.html). Treafik will automatically handle renewing the certificates for you behind the scenes, so that's one less thing you'll have to worry about!

## Conclusion

In this tutorial, we walked through how to containerize a Django application with Postgres for development. We also created a production-ready Docker Compose file, set up Traefik and Let's Encrypt to serve the application via HTTPS, and enabled a secure dashboard to monitor our services.

In terms of actual deployment to a production environment, you'll probably want to use a:

1. Fully-managed database service -- like [RDS](https://aws.amazon.com/rds/) or [Cloud SQL](https://cloud.google.com/sql/) -- rather than managing your own Postgres instance within a container.
1. Non-root user for the services