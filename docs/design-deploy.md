# Design: getting the platform off one laptop (task 04)

**Goal.** (1) No deployment depends on a person's laptop. (2) For any change in production we can
answer: what changed, who proposed it, who approved it, when it was applied, by which identity.

**Constraints that shape this.** One platform engineer. Product engineers keep committing to this
repo and must not be blocked. Small tool budget. Everything we need already exists in GitHub and
AWS; the design adds no new product.

## 1. How a change reaches production

The repo is the source of truth; the cluster and the account follow it, never the other way
round. One flow for both `live/` (Terragrunt) and `apps/` (helmfile), differing only in the
command that runs.

```
PR opened ──► CI: lint, validate, tests, consistency checks (today's ci.yml)
          ──► plan:  terragrunt plan  (live/)   |  helmfile diff  (apps/)
              posted as a PR comment, read-only AWS role via OIDC
          ──► review: CODEOWNERS requires platform approval for live/** and apps/*prod*/**;
              dev values files need any one reviewer
merge to main ──► apply workflow, per environment:
                   dev:  runs immediately
                   prod: GitHub environment "prod" → required reviewer (platform) → runs
               ──► terragrunt apply / helmfile apply with the environment's apply role
               ──► post-apply check: rollout status, worker logs, alarm state; failure = job red
               ──► PR gets a comment with the apply log link
```

What this gives the regulator, with no extra tooling: the PR (what, who proposed, reviewer, when
merged), the Actions run (who approved the prod gate, when applied, full log, 90-day retention →
export to S3 for longer), CloudTrail (every API call under role `gha-apply-prod`, session name =
the run id). Three records that cross-reference each other by PR number and run id.

Rules that make it hold: branch protection on `main` (no direct push, PR + CI required, linear
history); `apply` jobs run only from `main`; the apply role trusts **only** the `environment:prod`
subject, so a workflow edited in a PR cannot assume it; helmfile `wait: true` stays, and a timeout
is a **failed** deploy (the incident's misread); the repo is the only way to apply — once the
workflows are in place, the laptop path is removed by deleting the `acme` profile's admin access.

Emergency path: the same workflow with `workflow_dispatch`, same approval gate, same audit trail.
Faster than a laptop because nobody has to find the right kubeconfig at 02:00. A true
break-glass (console/CLI as a human) exists but pages the platform channel via a CloudTrail →
EventBridge rule on non-role console logins, and must be followed by a PR that makes the repo match.

## 2. AWS access

**Automation.** GitHub OIDC provider in the account (`modules/github-oidc-role`). Roles:

| Role | Trusted subject | Permissions | Used by |
|---|---|---|---|
| `gha-plan` | `repo:<org>/<repo>:pull_request` | `ReadOnlyAccess` + state read + lock table | plan / diff on PRs |
| `gha-apply-dev` | `ref:refs/heads/main` | admin-ish on dev resources (tagged `Environment=dev`), EKS access entry on `acme-dev` | apply on merge |
| `gha-apply-prod` | `environment:prod` | same for prod; initially broad, narrowed as the module set stabilises | apply after approval |

No access keys in repo secrets, ever. Tokens live for one job. `aws-actions/configure-aws-credentials`
sets the session name to the run id so CloudTrail lines up with the Actions log.

**Humans.** Today: IAM users, one of them admin with a key in 1Password. Target, in order:

1. Day 1: deactivate the departed engineer's key, MFA mandatory on every remaining IAM user,
   no new access keys (the `assumable-role` pattern from task 03 for scripts).
2. Month 1: IAM Identity Center with the company IdP (Google Workspace / whatever HR already
   uses). Permission sets: `PlatformAdmin` (me, MFA, 1 h sessions), `Developer` (read-only +
   dev write), `ReadOnly` (support, finance, auditors). Console and CLI via `aws sso login`.
   EKS access entries map the same groups to cluster roles; product engineers get `view` in
   prod and `edit` in dev.
3. Nobody, including me, applies to prod as a human in normal operation. The prod apply role is
   assumable only by the workflow. My own admin access is for break-glass and is alarmed.

## 3. What I will deliberately not do yet, and why

- **ArgoCD / Flux (GitOps pull).** The right long-term model for `apps/`, but it is a new
  component to run, secure and understand, and helmfile-from-Actions gives 90% of the value
  (no laptop, audit trail, diff on PR) for a day of work. Revisit when there are more than ~10
  releases or a second cluster.
- **Atlantis / Spacelift / Terraform Cloud.** Nicer plan UX; costs money or a server; GitHub
  environments already give the approval gate. Not while the budget is small.
- **Separate prod AWS account.** The strongest control for OJK and Budi's own TODO. It is a
  migration, not a config change, and needs the state buckets, OIDC, IAM Identity Center and the
  EKS clusters redone. Design it in month 2, do it when there is a second engineer or a quarter
  of calm.
- **Narrow `gha-apply-prod` to least privilege on day one.** It would break the first ten applies
  and I would widen it under pressure. Start broad, log what it uses (IAM Access Analyzer
  "generate policy" from CloudTrail), narrow monthly.
- **Automated apply for `modules/` changes across all stacks.** A module change fans out to every
  stack that uses it; plan them all on the PR (the workflow does) but apply stack by stack.

## 4. Rollout, without blocking anyone

| Step | What | Who notices |
|---|---|---|
| 1 (this PR) | `gha-plan` role + OIDC provider; `infra-plan.yml` posts `terragrunt plan` on PRs touching `live/` or `modules/`; root `terragrunt.hcl` works without the `acme` profile in CI; `apply.yml` removed (static keys, `checkout@v2`, `run-all apply`). Applies still from my laptop. | Nobody. PRs get a plan comment. |
| 2 (week 2) | Branch protection + CODEOWNERS. `helmfile diff` on PRs for `apps/`. | Product engineers: PRs need one review; prod paths need mine. Agreed with Rina first. |
| 3 (week 3) | `gha-apply-dev` + apply-on-merge for dev (`live/` and `apps/`). I stop applying dev from my laptop. | Claims team: dev changes land by merging, no "ask platform to apply". |
| 4 (week 4–5) | `gha-apply-prod` behind the `prod` environment with me as required reviewer. First prod applies are low-risk stacks (alerts topic, tags). Two weeks of laptop-and-workflow in parallel, then remove the laptop path. | Everyone: prod changes are visible as PR + approval + run. |
| 5 (month 2) | IAM Identity Center; delete remaining IAM users' keys; CloudTrail console-login alarm. | Humans log in with SSO. |
| 6 (month 3) | Access Analyzer-driven narrowing of apply roles; export Actions logs to S3 for retention; drift detection (`terragrunt plan` nightly, alert on non-empty). | Nobody, if it works. |

Each step is reversible by disabling one workflow or one branch rule. None of them changes a
running workload.

## Implemented in this PR (step 1)

`modules/github-oidc-role` (+ tests), `live/acme/ap-southeast-3/platform/prod/github-actions`
(`gha-plan`), `.github/workflows/infra-plan.yml`, root `live/terragrunt.hcl` profile handling,
`apply.yml` deleted. To activate: apply the `github-actions` stack from a laptop once (the last
chicken-and-egg apply), set the real `org/repo` in it, and open a PR.
