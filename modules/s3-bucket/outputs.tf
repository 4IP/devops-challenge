output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "KMS key used for SSE-KMS, or null for SSE-S3. Readers and writers need kms:Decrypt / kms:GenerateDataKey on it."
  value       = local.kms_key_arn
}
