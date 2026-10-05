import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import app as app_module
from app import app


def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_index():
    resp = client().get("/")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "aws-devops-portfolio-demo"


def test_health():
    resp = client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_burn():
    resp = client().get("/burn?seconds=1")
    assert resp.status_code == 200
    assert resp.get_json()["burned_seconds"] == 1


def test_burn_capped():
    resp = client().get("/burn?seconds=999")
    assert resp.get_json()["burned_seconds"] == 30


def test_crash_marks_unhealthy():
    c = client()
    try:
        resp = c.get("/crash")
        assert resp.status_code == 200

        health_resp = c.get("/health")
        assert health_resp.status_code == 500
        assert health_resp.get_json()["status"] == "unhealthy"
    finally:
        # /crash flips module-level state - reset it so other tests
        # (and re-runs) aren't affected by test order
        app_module._healthy = True
