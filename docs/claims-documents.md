# Claim documents storage (task 03)

Storage for the files customers upload in the new claim submission flow: KTP photos, hospital
receipts, medical documents. This is personal data of the most sensitive kind we hold (identity +
health), so the design starts from "who can read it and how do we prove that", not from "where
do we put it".

## What was built

| Stack (`live/acme/ap-southeast-3/claims/<env>/`) | Module | What |
|---|---|---|
| `claims-documents-bucket` | `s3-bucket` | `acme-claims-documents-{dev,prod}`: SSE-KMS with a dedicated rotating CMK, versioning, public access blocked, TLS-only, bucket-owner-enforced, lifecycle (below). Prod `force_destroy = false`. |
| `claims-api-iam` | `irsa-role` | Role for the claims backend (`claims-api` SA in `claims` ns): put/get/delete under `tmp/` and `claims/`, list bucket, `kms:GenerateDataKey`/`Decrypt`. |
| `claims-worker-iam` (changed) | `irsa-role` | Worker gets `s3:GetObject` on `claims/*` + `kms:Decrypt`. Prod queue policy scoped from `sqs:*` on `*` to the four actions on the queue ARN (dev already was). |
| `claims-documents-uploader-role` (dev only) | `assumable-role` (new) | Role Dimas/Rina assume with MFA for 1 h from laptop scripts. Put/get/list on the dev bucket. |

`modules/s3-bucket` was hardened for every bucket (public access block, encryption, TLS-only
policy, ownership controls are now unconditional). Applying it to the existing `reports-bucket`
adds those resources; nothing about the objects changes. Do that with a reviewed plan, not as a
side effect.

### Bucket layout

```
s3://acme-claims-documents-<env>/
  tmp/<upload-id>/<file>            presigned PUT from the app lands here; expires after 7 days
  claims/<claim-id>/<doc-type>/<file>   backend moves files here when the claim is submitted
```

The worker can only read `claims/`. Anything in `tmp/` is unsubmitted and never reaches OCR.
Versioning is on so an accidental overwrite or delete is recoverable; old versions expire after
30 days (prod) / 7 (dev).

### Upload flow

1. App asks `claims-api` for an upload URL for a document.
2. `claims-api` (IRSA, `claims-api-<env>` role) returns a presigned `PUT` for `tmp/<upload-id>/...`,
   valid for a few minutes, with the KMS key id in the signed headers.
3. App uploads directly to S3 over TLS. No AWS credentials ever leave the backend.
4. On submit, `claims-api` copies `tmp/...` → `claims/<claim-id>/...` and enqueues the
   `claims-documents` message the worker already consumes (`DOCUMENTS_BUCKET` env added to the
   worker values; the message carries the key).

### What is deliberately different from the request

**No IAM user with access keys.** Rina asked for the same thing Budi did for the reports bucket.
For this bucket that is a no:

- Long-lived keys for identity documents and medical records on laptops and in backend config
  is the single most likely way this data leaks, and it is the first thing an auditor will ask
  about. A key in a script cannot be tied to a person after the fact.
- The backend runs on EKS, so it gets credentials the same way the worker does (IRSA): nothing
  to store, nothing to rotate, every call attributable to the role.
- Laptop scripts get a **role assumed with MFA** for one hour, **dev only**. That is one extra
  command (`aws sts assume-role`) and produces a CloudTrail record with the engineer's name.
- Production documents are not accessed from laptops at all. If a support process needs to look
  at a document, that is a product feature with its own access control and audit log, not a
  bucket permission.

The `iam-user` module and `claims-reports-uploader` are untouched here; retiring that user is
on the takeover list (task 01).

## Assumptions (please correct me)

1. **The claims backend runs on EKS**, namespace `claims`, with a service account named
   `claims-api`. If it runs elsewhere (Lambda, EC2, another cluster), the role changes shape but
   the policy stays; tell me where and I'll adjust.
2. **Uploads go through the backend via presigned URLs**, not directly from the app with
   credentials. Cognito identity pools would be the alternative if the app must talk to S3
   without a backend hop; I'd want to know that before prod.
3. **Document identifier**: `claims/<claim-id>/<doc-type>/<file>`. Doc types I assumed: `ktp`,
   `receipt`, `medical`. Change freely; only the prefixes `tmp/` and `claims/` matter to IAM.
4. **Retention**: "as long as needed for the claim" is not something S3 can enforce by itself.
   There is **no expiration on `claims/`** right now, and there won't be until product says what
   "needed" means in days, per claim state (approved / rejected / withdrawn), and what the legal
   minimum is (OJK record-keeping vs. UU PDP data minimisation pull in opposite directions).
   Once defined, the backend tags objects with the claim outcome and a lifecycle rule per tag
   does the deletion — that is a small change on the infra side.
5. **Dev data is synthetic.** The dev bucket must not receive real customer documents; the
   laptop role exists because dev holds test data only.
6. **Trusted principals for the dev role** are the IAM users `dimas` and `rina`. These should
   become an SSO permission set when we have IAM Identity Center (task 04).
7. **Encryption**: a per-bucket CMK rather than the default S3 key, so access to documents can be
   cut at the key as well as the bucket, and key usage shows in CloudTrail. The `kms_key_arn`
   output is what every reader/writer role references.

## Not done yet / open questions for product

- Retention and deletion policy (assumption 4). Also: do customers have a right-to-erasure flow
  that must reach this bucket?
- S3 access logging and CloudTrail data events for the prod bucket: the module supports
  `logging_target_bucket`; needs a log bucket stack first. Should be in place before real data.
- Malware scanning on upload (GuardDuty Malware Protection for S3) before anything from the public
  internet reaches the worker.
- Object Lock / legal hold: only if compliance asks for immutability.
- The `claims-api` Helm release itself (values, SA) is the claims team's; add
  `serviceAccount.name: claims-api` + `roleArn` to it and CI will verify the match.

## Rollout

1. `dev`: `terragrunt run-all plan` under `claims/dev` → apply bucket, then `claims-api-iam`,
   `claims-documents-uploader-role`, then `claims-worker-iam` (adds permissions only).
   Claims team tests this week.
2. `prod`: bucket + `claims-api-iam` are new resources, safe to apply any time. The
   `claims-worker-iam` change in prod **narrows** the queue policy; plan must show only the
   expected statements, apply during working hours, watch the worker logs for 15 minutes.
   Rollback = revert the commit, apply again.

---

## Reply to Rina

> hi Rina! bucket is ready in dev, prod is one approval away. short version of what I built and
> two things I'm doing differently from what you asked:
>
> **what you get**
> - `s3://acme-claims-documents-dev` (and `-prod`): encrypted with its own KMS key, versioned,
>   no public access, TLS only. Layout: app uploads land in `tmp/<upload-id>/`, backend moves
>   them to `claims/<claim-id>/` on submit. `tmp/` self-cleans after 7 days.
> - claims-worker can already read `claims/` for OCR (same IRSA role, new permission, plus a
>   `DOCUMENTS_BUCKET` env var). Nothing to change on your side except reading the key from the
>   message.
> - a role for the backend (`claims-api-<env>`) that can write/move documents and sign upload URLs.
>   Your deployment needs a service account named `claims-api` in the `claims` namespace with the
>   role ARN annotation — same pattern as the worker, I can pair with Dimas on it.
>
> **what's different**
> 1. **no IAM user / access keys.** I know Budi did that for the reports bucket, but these files are
>    KTPs and medical records. A static key in a laptop script or backend config is the most likely
>    way that data walks out, and OJK will ask us who accessed what — a shared key can't answer
>    that. The backend doesn't need keys at all on EKS (it gets them the same way the worker does).
>    For your laptop scripts in dev I made `claims-documents-uploader-dev`: run
>    `aws sts assume-role` with your MFA, you get 1-hour credentials, done. One extra line in the
>    script; I'll send a snippet. For prod there's deliberately no laptop access — if support needs
>    to view documents, let's make that a feature with its own audit trail.
> 2. **retention: nothing expires in `claims/` yet.** "as long as needed for the claim" isn't a
>    number S3 can act on. I don't want to guess with medical data in either direction (delete too
>    early = regulatory problem, keep forever = UU PDP problem).
>
> **what I need from you / product**
> - retention rule in days per claim outcome (approved / rejected / withdrawn), and whether
>   customers can request deletion. once I have it, the lifecycle rule is a 10-minute change.
> - confirm the backend runs on EKS in the `claims` namespace (I assumed yes). if it's somewhere
>   else, tell me where and I'll adjust the role.
> - confirm dev only ever gets synthetic documents.
> - the IAM usernames of whoever needs the dev laptop role (I put you and Dimas).
>
> you can start testing in dev as soon as the PR is applied — ping me and I'll run it with you so
> we see the first upload go through together. 🙏
