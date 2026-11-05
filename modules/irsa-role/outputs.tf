output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "trusted_subjects" {
  description = "The system:serviceaccount:<namespace>:<name> subjects the trust policy accepts."
  value       = local.trusted_subjects
}
