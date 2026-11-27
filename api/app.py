# API server: reads buy messages from Kafka, saves them in MongoDB, returns the list
import json
import os
import threading
import time

# from fastapi import FastAPI
from fastapi import FastAPI, HTTPException
from kafka import KafkaConsumer
from pymongo import MongoClient

KAFKA = os.getenv("KAFKA", "kafka:9092")
MONGO = os.getenv("MONGO", "mongodb://mongo:27017")

# database "shop", collection "purchases"
purchases = MongoClient(MONGO).shop.purchases

app = FastAPI()


def consume():
    # Kafka can take a few seconds to start - keep trying until it's up
    while True:
        try:
            consumer = KafkaConsumer(
                "purchases",
                bootstrap_servers=KAFKA,
                group_id="api-server",         # Kafka remembers where this group stopped reading
                auto_offset_reset="earliest",  # first time: read from the start of the topic
                enable_auto_commit=False,      # we say "read" ourselves, only after Mongo has it
                value_deserializer=lambda v: json.loads(v),
            )
            break
        except Exception as e:
            print(f"Kafka not ready ({e}), trying again in 3s", flush=True)
            time.sleep(3)

    # every buy message -> one document in MongoDB
    for message in consumer:
        purchases.insert_one(message.value)
        # mark as read only after it's saved - a crash in between means it's read again, not lost
        consumer.commit()
        print("saved:", message.value, flush=True)


# read Kafka in the background, so the API can answer requests at the same time
# threading.Thread(target=consume, daemon=True).start()
reader = threading.Thread(target=consume, daemon=True)
reader.start()


@app.get("/getAllBoughtItems")
def get_all_bought_items():
    # all purchases, without MongoDB's internal _id
    return list(purchases.find({}, {"_id": 0}))


@app.get("/health")
def health():
    # if the Kafka reader died, say so - Kubernetes then restarts this pod
    if not reader.is_alive():
        raise HTTPException(status_code=503, detail="kafka reader stopped")
    return {"status": "ok"}