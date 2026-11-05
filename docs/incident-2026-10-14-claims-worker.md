# Incident 2026-10-14 — claim documents not processed (claims-worker down)

| | |
|---|---|
| **Severity** | SEV-1 (customer-facing, core claims flow stopped) |
| **Impact window** | Tue 13 Oct 17:43 WIB → Wed 14 Oct ~03:00 WIB (restore), backlog drained by ~06:00 WIB |
| **Detected by** | Customers → Customer Support (01:38 WIB) → Claims lead (02:10 WIB). Not by monitoring. |
| **Root cause** | Kubernetes service account renamed in prod without changing the IAM trust policy bound to it |
| **Owner** | Platform (Arief) |

All times WIB (UTC+7). Evidence in `incident/evidence/`.

---

## Part 1 — Restore runbook (what I ran tonight, in order)

### 0. Triage (5 min) — confirm it is not the database

Rina's hunch was the DB. Checked first, because a DB problem needs a different fix:

```sh
kubectl -n claims get pods                       # 30/30 pods CrashLoopBackOff since ~17:43
kubectl -n claims logs <pod> --previous          # worker connects to DB fine, then:
#   sqs: ReceiveMessage failed: WebIdentityErr ... AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
kubectl -n claims describe pod <pod> | grep -E 'Service Account|AWS_ROLE_ARN|Start Time'
#   Service Account: claims-worker-sa   AWS_ROLE_ARN: .../claims-worker-prod   Start Time: 17:43 WIB
git log -3 --stat                                # 17:38 Dimas: rename service account to claims-worker-sa
grep -n service_account live/acme/ap-southeast-3/claims/prod/claims-worker-iam/terragrunt.hcl
#   service_account = "claims-worker"           <- trust policy still bound to the OLD name
```

DB slow queries stopped at 15:29 WIB (reporting job), 2 hours before the outage; the worker log shows
a successful DB connection. Not the database.

**Diagnosis:** pods run as `claims-worker-sa`, IAM role `claims-worker-prod` only trusts
`system:serviceaccount:claims:claims-worker`, STS refuses, worker exits, kubelet restarts it, repeat.
Nothing consumes `claims-documents`: 48,213 messages queued, oldest from 17:38.

### 1. Decide the fix: revert the rename (not: patch IAM)

Two ways out. Patch the IAM trust policy to accept `claims-worker-sa` (forward fix), or put the
service account name back to `claims-worker` (revert). I chose **revert**:

- One-line change that is already reviewed by reality: this exact config ran fine until 17:38.
- Rollback is trivial and symmetric.
- It matches the IAM stack, the docs and dev. No prod IAM change at 02:30 with nobody to review it.
- The rename itself is cosmetic; it can be redone properly in daylight (see docs/claims-worker.md).

`kubectl rollout undo` is **not** an option: the chart creates the SA, so the Helm upgrade deleted
`claims-worker` and created `claims-worker-sa`. The previous ReplicaSet references an SA that no
longer exists. The fix has to go through Helm.

### 2. Cap the recovery rate before restoring

48k messages × 30 replicas × `WORKER_CONCURRENCY=4` × DB pool 8 would hit `claims-db.prod` with
up to ~240 connections at once, at night, right after a day with reporting load. I'd rather the
backlog takes 3 hours than find out the DB connection limit at 03:00. Pause KEDA at 5 replicas:

```sh
kubectl -n claims annotate scaledobject claims-worker autoscaling.keda.sh/paused-replicas=5
```

### 3. Apply the revert

```sh
git revert 8f3c2a1e --no-edit            # "chore(claims-worker): rename service account ..."
cd apps/acme-prod-cluster
helmfile -l name=claims-worker diff      # expect: ServiceAccount claims-worker-sa -> claims-worker,
                                         #         Deployment serviceAccountName changed. Nothing else.
helmfile -l name=claims-worker apply
git push origin main                      # the repo must match the cluster before I go to bed
```

### 4. Verify it worked (10 min)

```sh
kubectl -n claims get pods -w                              # new ReplicaSet, 5/5 Running, READY 1/1, 0 restarts
kubectl -n claims logs deploy/claims-worker --since=2m     # "sqs: polling ...", then "processed message ..." lines
aws sqs get-queue-attributes --queue-url https://sqs.ap-southeast-3.amazonaws.com/111111111111/claims-documents \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
#   NotVisible > 0 (messages in flight), total decreasing on repeat
aws cloudwatch describe-alarms --alarm-names claims-documents-oldest-message-age --query 'MetricAlarms[0].StateValue'
#   ALARM -> OK once the oldest message is < 15 min old (that is the end of the backlog, not the start of recovery)
aws sqs get-queue-attributes --queue-url .../claims-documents-dlq --attribute-names ApproximateNumberOfMessages
#   watch the DLQ: a sudden rise means the worker is failing on message content, stop and look
```

Ask Rina to confirm in the claims dashboard that documents move out of "documents uploaded".

Then release the throttle gradually, watching DB connections / CPU on `claims-db.prod`:

```sh
kubectl -n claims annotate scaledobject claims-worker autoscaling.keda.sh/paused-replicas=15 --overwrite
# ... 15 min, DB healthy ...
kubectl -n claims annotate scaledobject claims-worker autoscaling.keda.sh/paused-replicas-   # back to KEDA
```

### 5. Rollback if it did not work

If pods still crash after step 3 with the same STS error, the IAM side is not what the repo says
(someone changed the trust policy by hand). Then:

```sh
aws iam get-role --role-name claims-worker-prod --query 'Role.AssumeRolePolicyDocument'   # read what prod actually trusts
helmfile -l name=claims-worker apply   # with serviceAccount.name set to whatever the policy trusts
```

If pods crash with a *different* error, revert the revert (`git revert HEAD`, `helmfile apply`),
which returns to the known state (down, but not worse), and work from the new error. In every
case leave `paused-replicas` on until the worker is proven healthy.

### What is at stake if this slips

`MessageRetentionPeriod` on the queue is 4 days. Messages from Tuesday 17:38 expire **Saturday
17:38 WIB**. After that, the claim documents are gone from the queue and customers have to re-upload.

---

## Part 2 — Postmortem (for Rina and management)

### Summary

From Tuesday 17:43 until Wednesday ~03:00, no uploaded claim document was processed. A routine
rename of a Kubernetes service account for the claims-worker was applied to production without the
matching IAM change, so every worker process was refused AWS credentials and crashed on start.
48,213 documents queued up. We have an alarm for exactly this condition and it fired at 18:12
Tuesday, but it was not connected to any notification channel. We learned about the outage from
customers, 8 hours later.

### Impact

- ~9 hours of no claim document processing (OCR). Every claim submitted in that window stuck at
  "documents uploaded". 48,213 documents queued.
- 40+ customer support tickets by 01:38 Wednesday; customers who uploaded hospital receipts saw
  nothing happen.
- No data was lost: SQS kept every message (retention 4 days). Backlog fully processed by ~06:00.
- Nobody in claims engineering or platform was aware until 02:10.

### Timeline (WIB)

| Time | What happened |
|---|---|
| Tue 14:22–15:47 | Claims dashboard slow; monthly report job scanning `claim_documents`. Unrelated, resolved by itself. |
| Tue 17:38 | Dimas commits a rename of the claims-worker service account `claims-worker` → `claims-worker-sa` (naming consistency with the payments repo). |
| Tue 17:40 | Dimas runs `helmfile apply` against prod from his laptop. Helm creates the new SA, deletes the old one, rolls the deployment. |
| Tue 17:43 | New pods start, fail `sts:AssumeRoleWithWebIdentity`, exit. **Outage begins.** helmfile `wait: true` waits for pods that never become ready. |
| Tue 17:50 | helmfile times out after 10 min. Read as a flaky-VPN problem. |
| Tue 17:55 | Second `helmfile apply`: "nothing to change" (the release *was* already updated). Taken as success. Dimas goes home. |
| Tue 17:55–18:12 | `claims-documents-oldest-message-age` crosses 900 s for 3 periods → **ALARM at 18:12**. Alarm has no actions. Nobody is notified. |
| Tue 18:00 → Wed 02:00 | KEDA sees the queue growing and scales the deployment to 30 replicas — all crash-looping (90+ restarts each). Queue grows to 48k. |
| Wed 01:38 | Ayu (Customer Support) reports 40+ tickets in #claims-eng. |
| Wed 02:10 | Rina pages platform. |
| Wed 02:15–02:40 | Diagnosis (above). DB ruled out. |
| Wed ~02:50 | Service account reverted, workers healthy at 5 replicas, backlog draining. |
| Wed ~03:30 | KEDA released, 30 replicas. |
| Wed ~06:00 | Queue empty, alarm OK. |

### Root cause

The claims-worker gets its AWS permissions through IRSA: the IAM role `claims-worker-prod` trusts
exactly one Kubernetes identity, `system:serviceaccount:claims:claims-worker`. The service account
name is therefore part of the security configuration, but it lives in a different place (`apps/`
Helm values) than the policy that depends on it (`live/` Terragrunt). A change to one without the
other breaks authentication for every pod. Nothing in the repo, CI, or deploy process checked that
the two agree; the only guard was a sentence in `docs/claims-worker.md`.

### Contributing factors (why it took 9 hours)

1. **The alarm had no subscribers.** `claims-documents-oldest-message-age` exists in code
   (`modules/sqs-queue`) with `alarm_actions = []`. Budi's notes say he "meant to point it at
   #claims-alerts and never did".
2. **The deploy signal was misread.** helmfile's 10-minute timeout *was* the deployment failing
   (pods never ready). It looked like a network problem, and the second run reporting "no
   changes" looked like success. There is no post-deploy check and no CrashLoop alert.
3. **Production is applied from laptops, outside working hours, without a second pair of eyes.**
   Any engineer with repo write access can run `helmfile apply` against prod. There is no plan
   review, no approval, and the repo is not required to match the cluster.
4. **No worker health signal.** KEDA kept scaling a dead deployment to 30 replicas for 8 hours;
   that was visible to nobody. There is no "pods crash-looping" or "no messages consumed" alert.
5. **The database red herring** cost ~15 minutes at 02:10, because the only operational signal
   anyone had seen that day was slow queries.

This is not about Dimas. The rename was reasonable, the docs warning was easy to miss, and the
tooling gave him a misleading answer. The system made the mistake easy and invisible.

### Follow-up actions

I own all of these. Ordered by how much they reduce the chance of the *next* customer-detected outage
per hour of work.

| # | Action | Status | Effort | Why this order |
|---|---|---|---|---|
| 1 | Connect the SQS alarm to people: SNS topic `claims-alerts-prod` → email on-call + Rina, and `#claims-alerts` via AWS Chatbot (`modules/alert-topic`, `live/.../claims/*/alerts`) | **Done in this PR** | 2 h | Turns 8 h undetected into 15 min. Works for any future consumer failure, not just this one. |
| 2 | CI check that every IRSA-backed release's service account matches its IAM trust policy (`scripts/check-irsa-service-accounts.py`, new `consistency` job) | **Done in this PR** | 1 h | Catches this exact class of change in the PR, before anything is applied. |
| 3 | Support safe service-account renames in `modules/irsa-role` (`additional_service_accounts`, trust both names during a transition) + `terraform test` + rename procedure in `docs/claims-worker.md` | **Done in this PR** | 1 h | Makes the right thing possible, so people don't have to work around the guard. |
| 4 | Redo the `claims-worker-sa` rename properly with Dimas (IAM first, then values, then clean up), so the naming convention he wanted actually lands | Next week | 1 h | Closes the loop on the original intent; also a good walkthrough of the new procedure. |
| 5 | Resource requests/limits for claims-worker prod (pods are BestEffort; the worker itself warns about it) and pin the prod image tag | Next sprint | 2 h | Cheap, and the incident response was harder because 30 BestEffort pods thrashed on the nodes. |
| 6 | Deploy from CI, not laptops: plan/diff on PR, apply on merge with a required reviewer for prod. Also fixes "repo ≠ cluster" and gives OJK an audit trail | Design in task 04, first step within 30 days | 2–3 days | The structural fix; too big to do tonight, which is why 1–3 come first. |
| 7 | Kubernetes-side alerting (CrashLoopBackOff, deployment unavailable > 5 min) via kube-prometheus-stack or CloudWatch Container Insights, to the same SNS topic | 30–60 days | 1–2 days | Second detection path that does not depend on a queue metric. |
| 8 | Scope the prod worker role from `sqs:*` on `*` to the queue's actions on the queue's ARN (dev already is) | With task 01 fixes | 30 min | Not causal here, but it was in front of me and it is prod. |

### What we are deliberately not doing

- Not adding an "allow any SA in namespace" wildcard to the trust policy. It would have prevented
  this outage, and it would also let any pod in `claims` read claim documents.
- Not blocking product engineers from touching `apps/`. They should be able to ship; the fix is to
  make the dangerous change fail in CI and to review prod applies, not to add a gate on people.

### Lessons

- An alarm nobody receives is documentation, not monitoring. Every alarm needs an action, and
  "who gets paged" is part of the definition of done for any new queue or service.
- A deploy that times out is a failed deploy until proven otherwise. "No changes" on the retry
  means the first attempt went through.
- When a security boundary (IAM trust) depends on a name defined somewhere else, the agreement
  between the two must be enforced by a machine.
