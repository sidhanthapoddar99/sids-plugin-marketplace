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
Workers: auto-restarting processes (container `restart: always` / systemd `Restart=always`) launched by the `scripts/cloud/` wrapper.

### Online inference

A persistent web endpoint with autoscaling. Traffic-driven scale-up; idle scale-down. Spot is harder here — preemption causes a brief outage.

```
                  ┌──────────┐         ┌──────────┐
[ Client ] → [ LB ] → [ Replicas: 1..N on spot or mixed ]
                  └──────────┘         └──────────┘
```

LB: nginx, traefik, or the cloud provider's LB.
Replicas: behind a service-discovery mechanism that survives instance churn.

## The redeploy-on-preemption pattern

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

The controller is itself **on-demand** (no preemption). It watches the spot replicas, and when one disappears it kicks off a new one and registers it with the LB. It can be a small script on a cheap VM or the custom orchestrator CLI (`references/2-repo/07-ml-orchestration/00_custom-orchestrator.md`).

## Scale up/down policies

| Policy | When |
|---|---|
| **Step scaling** — +1 replica per traffic threshold | Latency-sensitive workloads, predictable spikes |
| **Target tracking** — keep utilisation at X% | Variable traffic; most common |
| **Scheduled** — N replicas during business hours | Predictable daily traffic |
| **None** — fixed N replicas always | Steady state; simpler |

`scale_down_after` matters more than scale-up policy for cost. Aggressive scale-down (1–5 min idle) is the lever.

## Health checks

Required regardless of tooling:

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
- Forgetting the readiness probe — LB sends traffic to a still-loading replica
- Aggressive scale-down on slow-loading models — flap city (scale down, then immediately need to scale up while the new replica is still loading)
- Cold-loading the model on every request — load once at startup
- Using spot for low-latency SLA endpoints — pick on-demand or accept the SLA hit
