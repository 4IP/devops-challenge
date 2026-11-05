> **Status (Nov 2026):** this is Budi's description and is being replaced. The target flow is in
> [design-deploy.md](./design-deploy.md). `apply.yml` has been removed; `infra-plan.yml` posts a
> `terragrunt plan` on PRs. Applies are still manual (platform engineer) until step 3/4 of the rollout.

# How we deploy

I apply from my laptop. That is the source of truth.

1. Change `live/` or `apps/`.
2. `terragrunt plan` / `helmfile diff` locally.
3. Apply if it looks right.
4. Commit after, or before — whichever. I usually commit after a successful apply so the
   repo matches AWS.

There is a draft workflow at `.github/workflows/apply.yml`. I started it so we wouldn't
need my laptop. It kept failing on push to main, so I switched it to `workflow_dispatch`
only. It is not finished and I have not used it for a real change. Do not turn auto-apply
back on until someone reviews it.

Product engineers have write access to `main`. They sometimes helmfile-apply their own
values. If something in the cluster does not match the repo, ask in #platform.

## Access

I am an AdministratorAccess IAM user (`budi`). The access key is in 1Password under
"AWS / budi". When I leave, rotate that key and keep using the same user, or create a
new one the same way.

CI does not have AWS credentials yet. I was going to add an IAM user for GitHub Actions
and put the keys in repo secrets.
