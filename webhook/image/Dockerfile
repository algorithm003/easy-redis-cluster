
FROM python:3.7.4-slim
ENV PYTHONUNBUFFERED=1 APP_PATH="app"

ADD ./requirements.txt /${APP_PATH}/requirements.txt
ADD ./webhook.py /${APP_PATH}/webhook.py

WORKDIR /${APP_PATH}
RUN apt-get update -yqq \
    && pip3 install --no-cache-dir -U pip setuptools \
    && pip3 install --no-cache-dir -r requirements.txt

CMD ["python3", "webhook.py"]
