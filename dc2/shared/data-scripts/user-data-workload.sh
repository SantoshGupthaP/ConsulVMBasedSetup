#!/bin/bash

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -ex

apt-get update -y
apt-get install -y python3 python3-pip

pip3 install flask gunicorn

mkdir -p /opt/app

cat << 'PY_SCRIPT' > /opt/app/workload_app.py
from flask import Flask, make_response
import random

app = Flask(__name__)

@app.route('/health')
def health_check():
    if random.random() < 0.95:
        return make_response("OK", 200)
    else:
        return make_response("Service Unavailable", 503)
PY_SCRIPT

cd /opt/app
nohup gunicorn --workers 2 --bind 0.0.0.0:8080 workload_app:app &