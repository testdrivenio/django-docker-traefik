# Dockerizing FastAPI with Postgres, Uvicorn, and Traefik

In this tutorial, we look at how to set up FastAPI with Postgres, Uvicorn, and Docker. For production environments, we'll add on Gunicorn, Traefik, and Let's Encrypt.

## Project Setup

Start by creating a project directory:

```sh
$ mkdir fastapi-docker-traefik && cd fastapi-docker-traefik
$ python3.9 -m venv venv
$ source venv/bin/activate
```

> Feel free to swap out virtualenv and Pip for [Poetry](https://python-poetry.org/) or [Pipenv](https://pipenv.pypa.io/). For more, review [Modern Python Environments](/blog/python-environments/).


Then, create the following files and folders:

```sh
├── app
│   ├── __init__.py
│   └── main.py
└── requirements.txt
```

Add [FastAPI](https://fastapi.tiangolo.com/) and [Uvicorn](https://www.uvicorn.org/), an ASGI server, to *requirements.txt*:

```
fastapi==0.63.0
uvicorn==0.13.4
```

Install them:

```sh
(venv)$ pip install -r requirements.txt
```

Next, let's create a simple FastAPI application in *app/main.py*:

```python
# app/main.py

from fastapi import FastAPI

app = FastAPI(title="FastAPI, Docker, and Traefik")


@app.get("/")
def read_root():
    return {"hello": "world"}
```

Run the application:

```sh
(venv)$ uvicorn app.main:app
```

Navigate to [127.0.0.1:8000](http://127.0.0.1:8000). You should see:


```json
{
    "hello": "world"
}
```

Kill the server once done. Exit then remove the virtual environment as well.

## Docker

Install [Docker](https://docs.docker.com/install/), if you don't already have it, then add a *Dockerfile* to the project root:

```Dockerfile
# Dockerfile

# pull the official docker image
FROM python:3.9.4-slim

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
    command: uvicorn app.main:app --host 0.0.0.0
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

Navigate to [http://localhost:8008](http://localhost:8008) to again view the hello world sanity check.

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
    command: bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; uvicorn app.main:app --host 0.0.0.0'
    volumes:
      - .:/app
    ports:
      - 8008:8000
    environment:
      - DATABASE_URL=postgresql://fastapi_traefik:fastapi_traefik@db:5432/fastapi_traefik
    depends_on:
      - db
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=fastapi_traefik
      - POSTGRES_PASSWORD=fastapi_traefik
      - POSTGRES_DB=fastapi_traefik

volumes:
  postgres_data:
```

To persist the data beyond the life of the container we configured a volume. This config will bind `postgres_data` to the "/var/lib/postgresql/data/" directory in the container.

We also added an environment key to define a name for the default database and set a username and password.

> Review the "Environment Variables" section of the [Postgres Docker Hub page](https://hub.docker.com/_/postgres) for more info.

Take note of the new command in the `web` service:

```sh
bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; uvicorn app.main:app --host 0.0.0.0'
```

`while !</dev/tcp/db/5432; do sleep 1` will continue until Postgres is up. Once up, `uvicorn app.main:app --host 0.0.0.0` runs.

Next, add a new file called *config.py* to the "app" directory, where we'll define environment-specific [configuration](https://fastapi.tiangolo.com/advanced/settings/) variables:

```python
# app/config.py

import os

from pydantic import BaseSettings, Field


class Settings(BaseSettings):
    db_url: str = Field(..., env='DATABASE_URL')

settings = Settings()
```

Here, we defined a `Settings` class with a `db_url` attribute. [BaseSettings](https://pydantic-docs.helpmanual.io/usage/settings/), from pydantic, validates the data so that when we create an instance of `Settings`, `db_url` will be automatically loaded from the environment variable.

> We could have used `os.getenv()`, but as the number of environment variables increases, this becomes very repetitive. By using a `BaseSettings`, you can specify the environment variable name and it will automatically be loaded.
>
> You can learn more about pydantic settings management [here](https://pydantic-docs.helpmanual.io/usage/settings/).

We'll use ormar for communicating with the database.

Add [ormar](https://collerek.github.io/ormar/), an async mini ORM for Python, to *requirements.txt* along with asyncpg and psycopg2:

```
asyncpg==0.22.0
fastapi==0.63.0
ormar==0.10.5
psycopg2-binary==2.8.6
uvicorn==0.13.4
```

> Feel free to swap ormar for the ORM of your choice. Looking for some async options? Check out the [Awesome FastAPI repo](https://github.com/mjhea0/awesome-fastapi#databases) and [this Twitter thread](https://twitter.com/testdrivenio/status/1383457727003783173).

Next, create a *app/db.py* file to set up a model:

```python
# app/db.py

import databases
import ormar
import sqlalchemy

from .config import settings

database = databases.Database(settings.db_url)
metadata = sqlalchemy.MetaData()


class BaseMeta(ormar.ModelMeta):
    metadata = metadata
    database = database


class User(ormar.Model):
    class Meta(BaseMeta):
        tablename = "users"

    id: int = ormar.Integer(primary_key=True)
    email: str = ormar.String(max_length=128, unique=True, nullable=False)
    active: bool = ormar.Boolean(default=True, nullable=False)


engine = sqlalchemy.create_engine(settings.db_url)
metadata.create_all(engine)
```

This will create a pydanic model and a SQLAlchemy table.

ormar uses [SQLAlchemy](https://www.sqlalchemy.org/) for creating databases/tables and constructing database queries, [databases](https://github.com/encode/databases) for executing the queries asynchronously, and [pydantic](https://pydantic-docs.helpmanual.io/) for data validation. Note that each `ormar.Model` is also a `pydantic.BaseModel`, so all pydantic methods are also available on a model. Since the tables are created using SQLAlchemy (under the hood), database migration is possible via [Alembic](https://alembic.sqlalchemy.org/en/latest/).

> Check out [Alembic usage](https://collerek.github.io/ormar/models/migrations/#alembic-usage), from the official ormar documentation, for more on using Alembic with ormar.

Next, update *app/main.py* to connect to the database and add a dummy user:

```python
# app/main.py

from fastapi import FastAPI

from app.db import database, User


app = FastAPI(title="FastAPI, Docker, and Traefik")


@app.get("/")
async def read_root():
    return await User.objects.all()


@app.on_event("startup")
async def startup():
    if not database.is_connected:
        await database.connect()
    # create a dummy entry
    await User.objects.get_or_create(email="test@test.com")


@app.on_event("shutdown")
async def startup():
    if database.is_connected:
        await database.disconnect()
```

Here, we used FastAPI's [event handlers](https://fastapi.tiangolo.com/advanced/events/) to create a database connection. `@app.on_event("startup")` creates a database connection pool before the app starts up.

```python
await User.objects.get_or_create(email="test@test.com")
```

The above line in the startup event adds a dummy entry to our table once the connection has been established. `get_or_create` makes sure that the entry is created only if it doesn't already exist.

The shutdown event closes all connections to the database. We also added a route to display all the entries in the `users` table.

Build the new image and spin up the two containers:

```sh
$ docker-compose up -d --build
```

Ensure the `users` table was created:

```sh
$ docker-compose exec db psql --username=fastapi_traefik --dbname=fastapi_traefik

psql (13.2)
Type "help" for help.

fastapi_traefik=# \l
                                              List of databases
      Name       |      Owner      | Encoding |  Collate   |   Ctype    |          Access privileges
-----------------+-----------------+----------+------------+------------+-------------------------------------
 fastapi_traefik | fastapi_traefik | UTF8     | en_US.utf8 | en_US.utf8 |
 postgres        | fastapi_traefik | UTF8     | en_US.utf8 | en_US.utf8 |
 template0       | fastapi_traefik | UTF8     | en_US.utf8 | en_US.utf8 | =c/fastapi_traefik                 +
                 |                 |          |            |            | fastapi_traefik=CTc/fastapi_traefik
 template1       | fastapi_traefik | UTF8     | en_US.utf8 | en_US.utf8 | =c/fastapi_traefik                 +
                 |                 |          |            |            | fastapi_traefik=CTc/fastapi_traefik
(4 rows)


fastapi_traefik=# \c fastapi_traefik
You are now connected to database "fastapi_traefik" as user "fastapi_traefik".

fastapi_traefik=# \dt
            List of relations
 Schema | Name  | Type  |      Owner
--------+-------+-------+-----------------
 public | users | table | fastapi_traefik
(1 row)

fastapi_traefik=# \q
```

You can check that the volume was created as well by running:

```sh
$ docker volume inspect fastapi-docker-traefik_postgres_data
```

You should see something similar to:

```sh
[
    {
        "CreatedAt": "2021-04-29T12:41:19Z",
        "Driver": "local",
        "Labels": {
            "com.docker.compose.project": "fastapi-docker-traefik",
            "com.docker.compose.version": "1.29.0",
            "com.docker.compose.volume": "postgres_data"
        },
        "Mountpoint": "/var/lib/docker/volumes/fastapi-docker-traefik_postgres_data/_data",
        "Name": "fastapi-docker-traefik_postgres_data",
        "Options": null,
        "Scope": "local"
    }
]
```

Navigate to [127.0.0.1:8008](http://127.0.0.1:8008). You should see:

```json
[
    {
        "id": 1,
        "email": "test@test.com",
        "active": true
    }
]
```

## Production Dockerfile

For deployment of our application, we need to add [Gunicorn](https://gunicorn.org/), a WSGI server, to spawn instances of Uvicorn. Rather than writing our own production *Dockerfile*, we can leverage [uvicorn-gunicorn](https://github.com/tiangolo/uvicorn-gunicorn-docker), a pre-built Docker image with Uvicorn and Gunicorn for high-performance web applications maintained by the core FastAPI author.

Create a new Dockerfile called *Dockerfile.prod* for use with production builds:

```Dockerfile
# Dockerfile.prod

FROM tiangolo/uvicorn-gunicorn:python3.8-slim

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
```

That's it. The `tiangolo/uvicorn-gunicorn:python3.8-slim` [image](https://github.com/tiangolo/uvicorn-gunicorn-docker/blob/0.6.0/docker-images/python3.8-slim.dockerfile) does much of the work for us. We just copied over the *requirements.txt* file, installed the dependencies, and then copied over all the project files.

Next, create a new compose file called *docker-compose.prod.yml* for production:

```yaml
# docker-compose.prod.yml

version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.prod
    ports:
      - 8009:80
    environment:
      - DATABASE_URL=postgresql://fastapi_traefik_prod:fastapi_traefik_prod@db:5432/fastapi_traefik_prod
    depends_on:
      - db
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data_prod:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=fastapi_traefik_prod
      - POSTGRES_PASSWORD=fastapi_traefik_prod
      - POSTGRES_DB=fastapi_traefik_prod

volumes:
  postgres_data_prod:
```

Compare this file to *docker-compose.yml*. What's different?

The `uvicorn-gunicorn` Docker image that we used uses a [prestart.sh](https://github.com/tiangolo/uvicorn-gunicorn-docker/tree/0.6.0#custom-appprestartsh) script to run commands before the app starts. We can use this to wait for Postgres.


Modify *Dockerfile.prod* like so:

```Dockerfile
# Dockerfile.prod

FROM tiangolo/uvicorn-gunicorn:python3.8-slim

RUN apt-get update && apt-get install -y netcat

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
```

Then, add a *prestart.sh* file to the root of the project:

```sh
# prestart.sh

echo "Waiting for postgres connection"

while ! nc -z db 5432; do
    sleep 0.1
done

echo "PostgreSQL started"

exec "$@"
```

Update the file permissions locally:

```sh
$ chmod +x prestart.sh
```

Bring [down](https://docs.docker.com/compose/reference/down/) the development containers (and the associated volumes with the `-v` flag):

```sh
$ docker-compose down -v
```

Then, build the production images and spin up the containers:

```sh
$ docker-compose -f docker-compose.prod.yml up -d --build
```

Test that [127.0.0.1:8009](http://127.0.0.1:8009) works.

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
    command: bash -c 'while !</dev/tcp/db/5432; do sleep 1; done; uvicorn app.main:app --host 0.0.0.0'
    volumes:
      - .:/app
    expose:  # new
      - 8000
    environment:
      - DATABASE_URL=postgresql://fastapi_traefik:fastapi_traefik@db:5432/fastapi_traefik
    depends_on:
      - db
    labels: # new
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(`fastapi.localhost`)"
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=fastapi_traefik
      - POSTGRES_PASSWORD=fastapi_traefik
      - POSTGRES_DB=fastapi_traefik
  traefik: # new
    image: traefik:v2.2
    ports:
      - 8008:80
      - 8081:8080
    volumes:
      - "./traefik.dev.toml:/etc/traefik/traefik.toml"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

volumes:
  postgres_data:
```

First, the `web` service is only exposed to other containers on port `8000`. We also added the following labels to the `web` service:

1. `traefik.enable=true` enables Traefik to discover the service
1. ``traefik.http.routers.fastapi.rule=Host(`fastapi.localhost`)`` when the request has `Host=fastapi.localhost`, the request is redirected to this service

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

Navigate to [http://fastapi.localhost:8008/](http://fastapi.localhost:8008/). You should see:

```json
[
    {
        "id": 1,
        "email": "test@test.com",
        "active": true
    }
]
```

You can test via cURL as well:

```sh
$ curl -H Host:fastapi.localhost http://0.0.0.0:8008
```

Next, check out the [dashboard](https://doc.traefik.io/traefik/operations/dashboard/) at [fastapi.localhost:8081](http://fastapi.localhost:8081):

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
    expose:  # new
      - 80
    environment:
      - DATABASE_URL=postgresql://fastapi_traefik_prod:fastapi_traefik_prod@db:5432/fastapi_traefik_prod
    depends_on:
      - db
    labels:  # new
      - "traefik.enable=true"
      - "traefik.http.routers.fastapi.rule=Host(`fastapi-traefik.yourdomain.com`)"
      - "traefik.http.routers.fastapi.tls=true"
      - "traefik.http.routers.fastapi.tls.certresolver=letsencrypt"
  db:
    image: postgres:13-alpine
    volumes:
      - postgres_data_prod:/var/lib/postgresql/data/
    expose:
      - 5432
    environment:
      - POSTGRES_USER=fastapi_traefik_prod
      - POSTGRES_PASSWORD=fastapi_traefik_prod
      - POSTGRES_DB=fastapi_traefik_prod
  traefik:  # new
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
      - "traefik.http.routers.dashboard.rule=Host(`dashboard-fastapi-traefik.yourdomain.com`) && (PathPrefix(`/`)"
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

1. ``traefik.http.routers.fastapi.rule=Host(`fastapi-traefik.yourdomain.com`)`` changes the host to the actual domain
1. `traefik.http.routers.fastapi.tls=true` enables HTTPS
1. `traefik.http.routers.fastapi.tls.certresolver=letsencrypt` sets the certificate issuer as Let's Encrypt

Next, for the `traefik` service, we added the appropriate ports and a volume for the certificates directory. The volume ensures that the certificates persist even if the container is brought down.

As for the labels:

1. ``traefik.http.routers.dashboard.rule=Host(`dashboard-fastapi-traefik.yourdomain.com`)`` defines the dashboard host, so it can can be accessed at `$Host/dashboard/`
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

1. [https://fastapi-traefik.youdomain.com](https://fastapi-traefik.youdomain.com)
1. [https://dashboard-fastapi-traefik.youdomain.com/dashboard](https://dashboard-fastapi-traefik.youdomain.com/dashboard)

Also, make sure that when you access the HTTP versions of the above URLs, you're redirected to the HTTPS versions.

Finally, Let's Encrypt certificates have a validity of [90 days](https://letsencrypt.org/2015/11/09/why-90-days.html). Treafik will automatically handle renewing the certificates for you behind the scenes, so that's one less thing you'll have to worry about!

## Conclusion

In this tutorial, we walked through how to containerize a FastAPI application with Postgres for development. We also created a production-ready Docker Compose file, set up Traefik and Let's Encrypt to serve the application via HTTPS, and enabled a secure dashboard to monitor our services.

In terms of actual deployment to a production environment, you'll probably want to use a:

1. Fully-managed database service -- like [RDS](https://aws.amazon.com/rds/) or [Cloud SQL](https://cloud.google.com/sql/) -- rather than managing your own Postgres instance within a container.
1. Non-root user for the services

You can find the code in the [fastapi-docker-traefik](https://github.com/testdrivenio/fastapi-docker-traefik) repo.
