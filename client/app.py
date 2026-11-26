# Client web server: takes the user's requests
#   GET /                   -> the shop page
#   POST /buy               -> sends the buy to Kafka (the API server saves it later)
#   GET /getAllBoughtItems  -> asks the API server for the list
import json
import os
import urllib.request
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.responses import FileResponse
from kafka import KafkaProducer
from pydantic import BaseModel

KAFKA = os.getenv("KAFKA", "kafka:9092")
API = os.getenv("API", "http://api:8000")

app = FastAPI()
producer = None


class Buy(BaseModel):
    user: str
    item: str
    price: float


def get_producer():
    # connect to Kafka on the first buy (Kafka may still be starting when this server starts)
    global producer
    if producer is None:
        producer = KafkaProducer(
            bootstrap_servers=KAFKA,
            value_serializer=lambda v: json.dumps(v).encode(),
        )
    return producer


@app.post("/buy")
def buy(order: Buy):
    message = order.model_dump()
    message["time"] = datetime.now(timezone.utc).isoformat()
    get_producer().send("purchases", message)
    get_producer().flush()   # wait until Kafka has it
    return {"status": "sent", "order": message}


@app.get("/getAllBoughtItems")
def get_all_bought_items():
    with urllib.request.urlopen(f"{API}/getAllBoughtItems", timeout=5) as response:
        return json.loads(response.read())


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/")
def page():
    # the frontend: one HTML page
    return FileResponse("index.html")