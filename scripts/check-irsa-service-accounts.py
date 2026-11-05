#!/usr/bin/env python3
"""
Fail CI when a Helm release's service account does not match the IRSA role it points at.

For every release in apps/*/helmfile.yaml that uses charts/service and sets
`serviceAccount.roleArn`, find the live/ stack that creates that role (modules//irsa-role with
`name = "<role>"`) and check that:

  * the release's service account name (serviceAccount.name, or the release name when empty —
    see charts/service/_helpers.tpl) is one of the stack's `service_account` /
    `additional_service_accounts`
  * the stack's `namespace`       == the release namespace

This is the guard for incident 2026-10-14: a one-line rename of the service account in
apps/acme-prod-cluster/values/claims-worker.yaml broke the IRSA trust policy and every
claims-worker pod. Run locally with:  python3 scripts/check-irsa-service-accounts.py
"""
import glob
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIVE = os.path.join(ROOT, "live")
APPS = os.path.join(ROOT, "apps")

HCL_STR = r'^\s*{key}\s*=\s*"([^"]*)"\s*$'


def hcl_string(text, key):
    m = re.search(HCL_STR.format(key=re.escape(key)), text, re.M)
    return m.group(1) if m else None


def hcl_string_list(text, key):
    m = re.search(r'^\s*' + re.escape(key) + r'\s*=\s*\[([^\]]*)\]', text, re.M | re.S)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else []


def irsa_stacks():
    """role name -> (path, namespace, trusted service accounts) for every irsa-role stack under live/."""
    stacks = {}
    for path in glob.glob(os.path.join(LIVE, "**", "terragrunt.hcl"), recursive=True):
        text = open(path).read()
        if "modules//irsa-role" not in text:
            continue
        name = hcl_string(text, "name")
        if not name:
            continue
        trusted = [hcl_string(text, "service_account")] + hcl_string_list(
            text, "additional_service_accounts"
        )
        stacks[name] = (
            os.path.relpath(path, ROOT),
            hcl_string(text, "namespace"),
            [sa for sa in trusted if sa],
        )
    return stacks


def service_releases():
    """Yield (helmfile, release name, namespace, values path) for charts/service releases."""
    for hf in sorted(glob.glob(os.path.join(APPS, "*", "helmfile.yaml"))):
        doc = yaml.safe_load(open(hf)) or {}
        for rel in doc.get("releases", []):
            chart = str(rel.get("chart", ""))
            if not chart.rstrip("/").endswith("charts/service"):
                continue
            for values in rel.get("values", []):
                if isinstance(values, str):
                    yield hf, rel["name"], rel.get("namespace", "default"), os.path.join(
                        os.path.dirname(hf), values
                    )


def main():
    stacks = irsa_stacks()
    problems = []
    checked = 0

    for hf, release, namespace, values_path in service_releases():
        values = yaml.safe_load(open(values_path)) or {}
        sa = values.get("serviceAccount") or {}
        role_arn = sa.get("roleArn") or ""
        if not role_arn:
            continue

        # charts/service: SA name defaults to the release name (nameOverride is not used here).
        sa_name = sa.get("name") or values.get("nameOverride") or release
        role_name = role_arn.rsplit("/", 1)[-1]
        rel_values = os.path.relpath(values_path, ROOT)
        checked += 1

        stack = stacks.get(role_name)
        if stack is None:
            problems.append(
                f"{rel_values}: roleArn {role_arn} has no irsa-role stack under live/ "
                f"(known roles: {', '.join(sorted(stacks)) or 'none'})"
            )
            continue

        stack_path, stack_ns, stack_sas = stack
        if sa_name not in stack_sas:
            problems.append(
                f"{rel_values}: serviceAccount.name is '{sa_name}' but {stack_path} trusts "
                f"{stack_sas}. Pods will fail sts:AssumeRoleWithWebIdentity. "
                f"Add the new name to additional_service_accounts in the IAM stack first "
                f"(see docs/claims-worker.md)."
            )
        if stack_ns != namespace:
            problems.append(
                f"{os.path.relpath(hf, ROOT)}: release '{release}' is in namespace '{namespace}' "
                f"but {stack_path} trusts namespace '{stack_ns}'."
            )

    for p in problems:
        print(f"ERROR: {p}")
    print(f"checked {checked} release(s) with IRSA, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
