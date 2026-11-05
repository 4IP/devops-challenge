# Taking over the platform (task 01)

What I inherited, what I think matters, what I fixed now, and the first 90 days. Written after
the incident (task 02) and the documents bucket (task 03), which already fixed several items;
those are marked. Everything here is from the repo only — I have not seen the AWS account, and
Budi's `docs/architecture.md` describes a platform that does not exist (ArgoCD, Karpenter, SOPS,
PagerDuty, MFA'd IAM users — none of it is in this repo), so I assume nothing in `docs/` is true
until I have checked it against the account.

## 1. Risks, prioritised

Urgency: **now** = this week, before anything else; **soon** = within 30 days; **later** = 30–90 days.
Effort is my time, as the only platform engineer.

| # | Risk | Why it matters for an insurer in Indonesia | Urgency | Effort | Status |
|---|---|---|---|---|---|
| 1 | **Budi's `AdministratorAccess` IAM user still exists, with an access key in a shared 1Password vault.** He left two weeks ago. `enable_cluster_creator_admin_permissions` likely makes the same user cluster-admin on both EKS clusters. | A departed employee's admin key to the account holding customer identity and health data. Also the first thing an OJK audit asks: who has admin, and can you prove it is only current staff. | now | 1 h | **Day-1 runbook below** (not code: the user is not in the repo) |
| 2 | **Prod secrets in git**: `DATABASE_URL` with the prod Postgres password in `apps/acme-prod-cluster/values/claims-worker.yaml`; Slack webhook in `live/.../guardduty-2slack/terragrunt.hcl`. Product engineers have write (and read) access to this repo, and the candidate fork of this very repo is public. | Anyone with repo read access has the prod DB password. Rotation is impossible without finding every place it is used. | now | 2 h + rotation | **Fixed in code**: chart `envFromSecrets`, values reference Secret `claims-worker-db`. Password and webhook **must be rotated** (runbook). |
| 3 | **GuardDuty → Slack drops every non-EC2 finding.** The Lambda assumed `instanceDetails`; IAM and S3 findings crashed it. The sample event that was being dropped is a HIGH S3 exfiltration by `claims-reports-uploader`. Slack HTTP errors were swallowed; no DLQ. | The security team's "some findings never show up" was literally the worst class of findings: credential misuse and data exfiltration on the bucket with customer reports. | now | 2 h | **Fixed in code**: resource-agnostic message, HTTP status check, tests for all three event types, EventBridge retry + DLQ, `logs:*` scoped to the function's log group. |
| 4 | **No one gets alerted.** The only alarm had no actions; no K8s-level alerting; nothing for the platform BU. | Found out from customers after 8 h (task 02). | now | done / soon | **Fixed for claims queues** (task 02). Platform alerts topic + CrashLoop alerting: soon. |
| 5 | **Prod is applied from laptops by anyone with repo write**, no plan review, repo ≠ cluster, `wait: true` timeouts misread as network problems. `apply.yml` is a half-finished `run-all apply` with static keys and `checkout@v2`. | Cause of the incident; also means there is no answer to "who changed prod, when, who approved". | now (design) / soon (impl) | 2–3 days | Design in task 04. Short-term: branch protection + CODEOWNERS on `live/` and `apps/*prod*`. |
| 6 | **Long-lived IAM user keys**: `claims-reports-uploader` with `s3:*` on the reports bucket, used from laptops; CI was going to get the same. | Static keys on laptops are how `Exfiltration:S3/AnomalousBehavior` happens (see #3's sample event). | soon | 3 h | `assumable-role` module exists now (task 03). Migrate the claims team's scripts to it, delete the user. |
| 7 | **EKS API endpoint public to `0.0.0.0/0`** on both clusters. | Cluster API reachable from the internet; auth is still required, but one leaked kubeconfig = cluster access. | soon | 2 h | Restrict to office/VPN CIDRs. Not done now: I do not know the CIDRs and would lock myself out. |
| 8 | **Prod worker ran `:latest`, BestEffort, no resource requests.** | Un-reproducible deploys (nodes pull different images), first pods evicted under pressure, 30 crash-looping pods thrashing nodes during the incident. | now | 30 min | **Fixed in code**: pinned to `1.14.2`, requests/limits set. Claims team's "push and restart" flow becomes "bump the tag by PR". |
| 9 | **IAM policies wider than needed**: worker `sqs:*` on `*` (prod), Lambda `logs:*` on `*`, uploader `s3:*`. | Blast radius when (not if) a credential leaks. | soon | done / 1 h | Worker and Lambda scoped (tasks 02/03/01). Uploader goes with #6. |
| 10 | **Buckets created with no baseline** (no encryption config, no public access block, no TLS policy, `force_destroy = true` on a prod bucket with customer reports). | A bucket policy typo away from public customer reports; `terragrunt destroy` deletes prod data. | soon | 1 h | `s3-bucket` module hardened (task 03). Apply to `reports-bucket` with a reviewed plan; set `force_destroy = false`. |
| 11 | **Single NAT gateway in prod**, EKS **1.29** (extended support, extra cost, no patches soon), node groups fixed size with cluster-autoscaler. | One AZ failure takes prod egress down; running an old K8s version for a regulated workload. | later | 1–2 days | Plan 1.29 → 1.31+ upgrade in dev first; NAT per AZ. |
| 12 | **Hand-made resources not in code**: `keda-operator-prod`, `acme-prod-cluster-autoscaler` roles are referenced from values but exist nowhere in `live/`. Probably more in the account. | Cannot be reviewed, cannot be rebuilt, drift unknown. | later | 2–3 days | Inventory the account (`aws iam list-roles`, drift check), import or recreate in code. |
| 13 | **No database backups verified** (`architecture.md` TODO), no DR story. | Claims data is the business. | later | 1–2 days | Confirm RDS automated backups + retention, test a restore once. |
| 14 | **No secrets management** (SOPS mentioned but absent). Kubernetes Secrets are created by hand. | Every secret is a one-off, unrotated, undocumented. | later | 2 days | External Secrets Operator + SSM/Secrets Manager. |
| 15 | **No tests for the claims worker deployment, `checkov` is `soft_fail`**, CI does not run on `live/`. | Static checks exist but do not block. | later | 1 day | Make checkov fail on HIGH; add `terragrunt validate`/`hclfmt` for `live/`. |

Things I looked at and decided are fine for now: KEDA + cluster-autoscaler setup, SQS/DLQ design,
Terragrunt layout (clear and worth keeping), remote state with locking, module tests pattern.

## 2. What I fixed now, and how to roll it out

Chosen because each is small, high-impact, and either does not touch running workloads or
touches them in a way I can verify in minutes.

| Fix | Files | Rollout | Rollback |
|---|---|---|---|
| GuardDuty Lambda handles all resource types, fails on Slack errors, DLQ + retries, scoped log permissions | `modules/guardduty-2slack/` | `terragrunt plan` in `platform/prod/guardduty-2slack`: expect Lambda code update, new log group (import if it already exists: `/aws/lambda/guardduty-2slack`), new SQS + policy, changed target. Apply, then `aws guardduty create-sample-findings` for `Exfiltration:S3/AnomalousBehavior` and check the channel. | Revert commit, apply. Nothing else depends on it. |
| Prod worker: pinned image, resources, DB URL from Secret | `charts/service` (0.4.0), `apps/*/values/claims-worker.yaml` | **Secret first**: `kubectl -n claims create secret generic claims-worker-db --from-literal=DATABASE_URL='<rotated url>'` in dev, `helmfile -l name=claims-worker apply`, confirm pods connect. Same in prod during working hours, watching `kubectl rollout status`. The image tag matches what runs, so the rollout is config-only. | `helm rollback claims-worker` (previous release still has the inline URL), or re-apply the previous values. |
| Worker IAM scoped, alerts wired, bucket baseline | tasks 02/03 | described there | described there |

### Day-1 runbook (not code)

Things I will do in the account before any of the above, in this order:

1. `aws iam list-access-keys --user-name budi` → deactivate (`update-access-key --status Inactive`),
   watch CloudTrail for 24 h for anything that was using it, then delete the key and the user.
   Remove him from `aws-auth`/access entries on both clusters.
2. Rotate the prod DB password (`claims` user) and put the new URL in the `claims-worker-db`
   Secret; rotate the Slack webhook. Both are in git history; the fork is public.
3. `aws iam list-users` / `list-roles`: who else has keys, what is not in the repo (#12).
4. Confirm GuardDuty is actually enabled and the Lambda exists (nothing in `docs/` is trusted).
5. Confirm RDS backups (#13).

## 3. First 90 days

**Days 1–14 — stop the bleeding, know what I own.** Day-1 runbook above. Apply tasks 02/03/01
fixes. Branch protection on `main` with CODEOWNERS for `live/` and `apps/acme-prod-cluster/`
(me as owner; product engineers keep write on everything else). Write down, in `docs/`, what
actually exists: replace `architecture.md` with the truth. Agree with Rina and the claims team on
one rule: prod changes go through a PR I review; dev is theirs.

**Days 15–45 — deployments off laptops (task 04).** GitHub Actions with OIDC to AWS (no static
keys), `terragrunt plan` / `helmfile diff` on every PR, apply on merge with a required reviewer
for prod environments. CloudTrail + PR history answer the OJK question. Platform alerts topic;
CrashLoop / deployment-unavailable alerting. Migrate the reports uploader from an IAM user to the
assumable role and delete the user. Restrict EKS endpoints.

**Days 46–90 — make it boring.** External Secrets + Secrets Manager, rotate everything once
through it. EKS upgrade path (dev first), NAT per AZ, import hand-made resources. Backup restore
test. Checkov blocking on HIGH. Then start the conversations that need budget or other people:
separate prod account (Budi's TODO; the right answer for OJK but not a one-person job),
IAM Identity Center instead of IAM users, and a second person who can apply to prod when I am
on leave.

**What I will not do in 90 days:** ArgoCD/GitOps migration, Karpenter, service mesh, a new
observability stack. Each is a good idea and each is a month of one person's time; none of them
addresses the risks above as directly as the items that do.
