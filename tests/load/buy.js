// k6 load test: many users buying at once, so the Kafka backlog grows and KEDA adds api pods
import http from "k6/http";
import { check } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 20 }, // warm up to 20 users
    { duration: "2m", target: 50 },  // push to 50 users
    { duration: "30s", target: 0 },  // calm down
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],   // fewer than 1% errors
    http_req_duration: ["p(95)<1000"], // 95% of buys under 1s
  },
};

const items = ["Sting", "Lembas Bread", "Horn of Gondor", "Elven Cloak of NAT"];

export default function () {
  const body = JSON.stringify({
    user: "k6",
    item: items[Math.floor(Math.random() * items.length)],
    price: 15,
  });
  const res = http.post("https://shop.mansuraforecast.online/buy", body, {
    headers: { "Content-Type": "application/json" },
  });
  check(res, { "bought": (r) => r.status === 200 });
}