import os
import socket
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

# flips to False after /crash. tried a couple of "actually kill the
# process" approaches first (see README/docs/incidents) and none of them
# reliably brought the container down in Fargate. this is simpler and
# more realistic anyway: real containers usually fail by going
# unresponsive/unhealthy, not by something inside them sending a signal
# to pid 1. the Dockerfile's HEALTHCHECK polls /health, so this makes
# Docker mark the container unhealthy, which is what actually gets ECS
# to replace the task.
_healthy = True


@app.route("/")
def index():
    return jsonify({
        "service": "aws-devops-portfolio-demo",
        "hostname": socket.gethostname(),
    })


@app.route("/health")
def health():
    if not _healthy:
        return jsonify({"status": "unhealthy"}), 500
    return jsonify({"status": "ok"}), 200


@app.route("/crash")
def crash():
    global _healthy
    _healthy = False
    return jsonify({
        "status": "marked unhealthy - waiting for the docker healthcheck to notice",
    }), 200


@app.route("/burn")
def burn():
    seconds = int(request.args.get("seconds", 5))
    if seconds > 30:
        seconds = 30

    end = time.time() + seconds
    while time.time() < end:
        pass

    return jsonify({"burned_seconds": seconds})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
