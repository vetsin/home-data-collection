FROM telegraf:1.24.1-alpine

ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache postgresql-dev gcc python3-dev musl-dev python3
RUN python3 -m ensurepip
RUN pip3 install --no-cache --upgrade pip setuptools
RUN pip3 install requests telegraf-pyplug sense_energy