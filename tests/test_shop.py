# End-to-end test: real Kafka + real Mongo in throwaway containers (Testcontainers)
# buy through the client -> Kafka -> api saves to Mongo -> api lists it
import importlib.util
import os
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from testcontainers.kafka import KafkaContainer
from testcontainers.mongodb import MongoDbContainer

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    # both apps are called app.py - load each under its own name
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def apps():
    with KafkaContainer("confluentinc/cp-kafka:7.6.0") as kafka, MongoDbContainer("mongo:8.0") as mongo:
        # the apps read these when they're loaded
        os.environ["KAFKA"] = kafka.get_bootstrap_server()
        os.environ["MONGO"] = mongo.get_connection_url()
        api = load("api_app", ROOT / "api" / "app.py")  # starts its Kafka reader in the background
        client = load("client_app", ROOT / "client" / "app.py")
        yield TestClient(client.app), TestClient(api.app)


def test_health(apps):
    client, api = apps
    assert client.get("/health").json() == {"status": "ok"}
    assert api.get("/health").json() == {"status": "ok"}


def test_bad_buy_is_rejected(apps):
    client, _ = apps
    # price missing -> FastAPI refuses it before it reaches Kafka
    assert client.post("/buy", json={"user": "test", "item": "Lembas"}).status_code == 422


def test_buy_is_saved(apps):
    client, api = apps
    response = client.post("/buy", json={"user": "test", "item": "Lembas", "price": 2.5})
    assert response.json()["status"] == "sent"

    # the api reads Kafka in the background - give it up to 60s (first connect is slow)
    for _ in range(60):
        items = [p["item"] for p in api.get("/getAllBoughtItems").json()]
        if "Lembas" in items:
            return
        time.sleep(1)
    pytest.fail("buy never reached Mongo")