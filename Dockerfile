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