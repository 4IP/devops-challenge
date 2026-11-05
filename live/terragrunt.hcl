# ---------------------------------------------------------------------------------------------------------------------
# ROOT TERRAGRUNT CONFIGURATION
# Every stack under live/ includes this file. Variables are loaded from the folder hierarchy:
#   account.hcl > region.hcl > bu.hcl > env.hcl
# ---------------------------------------------------------------------------------------------------------------------

locals {
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  bu_vars          = read_terragrunt_config(find_in_parent_folders("bu.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_id = local.account_vars.locals.aws_account_id
  # Laptops use the named profile; in GitHub Actions (CI=true) credentials come from the OIDC
  # role in the environment and a profile that does not exist would make the provider fail.
  aws_profile  = get_env("CI", "") == "true" ? "" : local.account_vars.locals.aws_profile
  profile_line = local.aws_profile == "" ? "" : "profile = \"${local.aws_profile}\""
  aws_region  = local.region_vars.locals.aws_region
  bu          = local.bu_vars.locals.bu
  environment = local.environment_vars.locals.environment
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
  ${local.profile_line}

  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Environment = "${local.environment}"
      BU          = "${local.bu}"
      ManagedBy   = "Terraform"
    }
  }
}
EOF
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = merge(
    {
      bucket         = "acme-terraform-state-${local.account_id}"
      key            = "${path_relative_to_include()}/terraform.tfstate"
      region         = local.aws_region
      encrypt        = true
      dynamodb_table = "acme-terraform-locks-${local.account_id}"
    },
    local.aws_profile == "" ? {} : { profile = local.aws_profile },
  )
}

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.bu_vars.locals,
  local.environment_vars.locals,
)
