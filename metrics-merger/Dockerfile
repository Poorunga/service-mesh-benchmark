FROM alpine
MAINTAINER Kinvolk

RUN apk add --update --no-cache python3 py-pip
RUN python3 -m pip install --upgrade pip
RUN pip3 install prometheus-http-client prometheus-client

COPY ./merger.py /
RUN chmod 755 ./merger.py

ENTRYPOINT ["/usr/bin/python3", "/merger.py"]
