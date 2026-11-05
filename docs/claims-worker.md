# Claims worker

Consumes `claims-documents` (prod) / `claims-documents-dev`. Each message is a claim
document that needs OCR.

- Chart: `charts/service`
- Values: `apps/acme-*/values/claims-worker.yaml`
- IAM: `live/.../claims/*/claims-worker-iam`
- Queue: `live/.../claims/*/claims-documents-queue`
- Alerts: `live/.../claims/*/alerts` (SNS topic the queue alarm publishes to)

## Service account and IRSA

The service account name is part of the IAM trust policy
(`system:serviceaccount:claims:claims-worker`, see `terragrunt output trusted_subjects` in the IAM
stack). The name in the values file must be one the IAM stack trusts;
`scripts/check-irsa-service-accounts.py` enforces this in CI.

To rename it (for example to follow an `<app>-sa` convention) without an outage:

1. IAM stack: add the new name to `additional_service_accounts`, `terragrunt apply`. The trust
   policy now accepts both names; running pods are unaffected.
2. Values file: change `serviceAccount.name`, `helmfile apply`. Pods roll over to the new name.
3. IAM stack: make the new name `service_account`, empty `additional_service_accounts`, apply.

Steps 1 and 2 can be one PR; CI fails if the values file names something the IAM stack does
not trust. On 2026-10-13 step 2 was done alone and every worker pod crash-looped for 8 hours.
See `docs/incident-2026-10-14-claims-worker.md`.

KEDA scales on queue depth. `identityOwner: operator` means KEDA's operator role is
what talks to SQS for the scaler (not the worker's role). That is why KEDA kept scaling the
deployment to 30 replicas during the incident even though the workers themselves could not
reach SQS.

## Alerts

`claims-documents-oldest-message-age` (threshold 900 s, prod) publishes ALARM and OK to
`claims-alerts-prod`: email to platform on-call + claims lead, and `#claims-alerts` through
AWS Chatbot. Dev alerts (threshold 1 h) go to email only.

## Image tags

Dev is pinned. Prod uses `latest` so the claims team can ship without asking me to
bump a tag. They push to ECR and restart the deployment. (Known risk, tracked in the takeover
notes — not changed as part of the incident fix.)
