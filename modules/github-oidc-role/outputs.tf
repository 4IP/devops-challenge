output "role_arn" {
  value = aws_iam_role.this.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "trusted_subjects" {
  description = "Full OIDC subject patterns the trust policy accepts."
  value       = [for s in var.subjects : "repo:${var.github_repository}:${s}"]
}
