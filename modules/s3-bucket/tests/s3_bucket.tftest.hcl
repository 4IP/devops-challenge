mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::test-bucket"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:ap-southeast-3:111111111111:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name = "test-bucket"
}

run "baseline_is_private_and_encrypted" {
  command = apply

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "Public access must be blocked on every bucket"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without a KMS key the bucket should still be encrypted (SSE-S3)"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0
    error_message = "No KMS key should be created unless requested"
  }
}

run "create_kms_key_switches_to_sse_kms" {
  command = apply

  variables {
    kms_key_arn = "create"
    versioning  = true
  }

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation == true
    error_message = "A rotating customer-managed key should be created"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Bucket should use SSE-KMS when a key is created"
  }

  assert {
    condition     = output.kms_key_arn == aws_kms_key.this[0].arn
    error_message = "kms_key_arn output should expose the created key"
  }
}

run "lifecycle_fields_are_optional" {
  command = apply

  variables {
    lifecycle_rules = [
      { id = "tmp", prefix = "tmp/", expiration_days = 7 },
      { id = "claims", prefix = "claims/", noncurrent_version_expiration_days = 30, abort_incomplete_multipart_days = 7 },
    ]
  }

  assert {
    condition     = length(tolist(aws_s3_bucket_lifecycle_configuration.this[0].rule)) == 2
    error_message = "One lifecycle rule per entry"
  }
}
