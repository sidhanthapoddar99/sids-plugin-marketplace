# Inference — long-running with auto-redeploy + scale up/down

Serving a model on spot GPUs needs different machinery than training. The job runs forever; instances get reclaimed; scaling up/down with traffic matters.

## Two shapes

### Batch inference

A queue of work + workers. Workers pull from the queue, process, write to a sink. Spot-friendly: a preempted worker leaves its in-flight task to be reprocessed.

```
                  ┌──────────┐
[ Producer ]  →  │ Queue    │  ←  [ Workers (spot) ]
                  └──────────┘            ↓
                                       [ Sink ]
```

Queue: Redis Streams, AWS SQS, GCP Pub/Sub, RabbitMQ.
Workers: dstack tasks or SkyPilot jobs, set to `restart: always`.

### Online inference

A persistent web endpoint with autoscaling. Traffic-driven scale-up; idle scale-down. Spot is harder here — preemption causes a brief outage.

```
                  ┌──────────┐         ┌──────────┐
[ Client ] → [ LB ] → [ Replicas: 1..N on spot or mixed ]
                  └──────────┘         └──────────┘
```

LB: nginx, traefik, cloud LB, dstack gateway.
Replicas: behind a service-discovery mechanism that survives instance churn.

## dstack — `type: service`

```yaml
# tasks/serve.dstack.yml
type: service
name: my-model-serve

python: "3.13"

env:
  - MODEL_URI

resources:
  gpu:
    name: A10, L4
    count: 1

# Public endpoint via dstack gateway (TLS handled)
gateway: my-gateway

# Autoscale
replicas: 1..4
scaling:
  metric: rps
  target: 10                   # scale up at 10 req/s/replica
  scale_down_after: 5m         # tear down idle replicas after 5min

# Spot is fine for inference if the model is stateless
spot_policy: auto

commands:
  - pip install -r requirements.txt
  - python -m my_project.serve --model "$MODEL_URI" --port 8000

port: 8000
```

`dstack apply -f tasks/serve.dstack.yml` brings up the service, registers it with the gateway, scales by RPS, and re-acquires instances on preemption.

## SkyPilot — `sky serve`

```yaml
# sky/serve.yaml
service:
  readiness_probe: /health
  replicas: 1
  spot_recovery: EAGER_NEXT_REGION
  resources:
    accelerators: A10:1
    use_spot: true

run: |
  python -m my_project.serve --port 8000
```

```bash
sky serve up sky/serve.yaml -y
```

## The redeploy-on-preemption pattern (custom orchestrator)

If neither tool fits, the pattern:

```
                    ┌──────────────────────┐
                    │ Controller (small VM)│
                    │ ── watches instances │
                    │ ── re-launches on    │
                    │    preemption        │
                    │ ── updates LB target │
                    └──────────────────────┘
                            ↓ ↑
              ┌────────────────────────────┐
              │ Spot inference replicas (N)│
              └────────────────────────────┘
```

The controller is itself **on-demand** (no preemption). It watches the spot replicas, and when one disappears it kicks off a new one and registers it with the LB. dstack and SkyPilot already implement this; building your own is for unusual cases.

## Scale up/down policies

| Policy | When |
|---|---|
| **Step scaling** — +1 replica per traffic threshold | Latency-sensitive workloads, predictable spikes |
| **Target tracking** — keep utilisation at X% | Variable traffic; most common |
| **Scheduled** — N replicas during business hours | Predictable daily traffic |
| **None** — fixed N replicas always | Steady state; simpler |

`scale_down_after` matters more than scale-up policy for cost. Aggressive scale-down (1–5 min idle) is the lever.

## Health checks

Required for either tool:

- HTTP `/health` endpoint returning 200 when ready
- Includes "model loaded" not just "process running"
- Slow enough to detect actual failures, fast enough to redirect traffic away

```python
# apps/<project>/src/serve.py
from fastapi import FastAPI

app = FastAPI()
_model = None  # lazy-loaded

@app.on_event("startup")
async def load_model():
    global _model
    _model = load_model_from_uri(os.environ["MODEL_URI"])

@app.get("/health")
def health():
    if _model is None:
        return {"status": "loading"}, 503
    return {"status": "ok"}
```

## Anti-patterns

- Stateful inference (per-user session data) on spot — preemption drops sessions; pin to on-demand or externalise state
- Forgetting `readiness_probe` — LB sends traffic to a still-loading replica
- Aggressive scale-down on slow-loading models — flap city (scale down, then immediately need to scale up while the new replica is still loading)
- Cold-loading the model on every request — load once at startup
- Using spot for low-latency SLA endpoints — pick on-demand or accept the SLA hit
