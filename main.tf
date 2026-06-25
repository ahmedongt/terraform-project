# ====================================================================
# FILE: main.tf (Production Automated Zero-Touch Deployment)
# ====================================================================

variable "cloudflare_api_token" {}
variable "cloudflare_zone_id" {}
variable "user_name" {}
variable "domain_name" {}
variable "instance_type" {}

variable "grafana_admin_user" {
  type      = string
  sensitive = true
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

terraform {
  backend "s3" {
    bucket       = "kali-terraform-state-storage-2026"
    key          = "state/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
  required_providers {
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    http       = { source = "hashicorp/http", version = "~> 3.0" }
  }
}

provider "cloudflare" { api_token = var.cloudflare_api_token }
provider "aws" { region = "us-east-1" }

locals {
  safe_user_name    = lower(replace(var.user_name, " ", "-"))
  monitoring_bucket = "monitoring-configs-and-stats-kali"
}

# --------------------------------------------------------------------
# S3 STORAGE INFRASTRUCTURE TIER
# --------------------------------------------------------------------
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${local.safe_user_name}-12345"
  force_destroy = true
}

# 1. Block Public Access (Ensures top-tier security compliance)
resource "aws_s3_bucket_public_access_block" "website_bucket_public_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Automated CORS Configuration (No more manual console edits!)
resource "aws_s3_bucket_cors_configuration" "website_bucket_cors" {
  bucket = aws_s3_bucket.website_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://ytthumbnail.site"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# 3. Lifecycle Policy (Deletes old thumbnails automatically after 1 day)
resource "aws_s3_bucket_lifecycle_configuration" "website_bucket_lifecycle" {
  bucket = aws_s3_bucket.website_bucket.id

  rule {
    id     = "auto-expire-temporary-thumbnails"
    status = "Enabled"

    expiration {
      days = 1
    }
  }
}

# --------------------------------------------------------------------
# IAM & DEPLOYMENT MANAGEMENT TIERS
# --------------------------------------------------------------------
resource "aws_iam_role" "web_admin_role" {
  name = "web_admin_role_${local.safe_user_name}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]  })
}

resource "aws_iam_role_policy" "s3_and_ssm_access" {
  name = "s3_and_ssm_access"
  role = aws_iam_role.web_admin_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.website_bucket.arn}",
          "${aws_s3_bucket.website_bucket.arn}/*",
          "arn:aws:s3:::${local.monitoring_bucket}",
          "arn:aws:s3:::${local.monitoring_bucket}/*"
        ]
      },
      {
        Action   = ["sts:GetCallerIdentity"]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" { 
  role       = aws_iam_role.web_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 
}

resource "aws_iam_role_policy_attachment" "ecr_readonly_attach" { 
  role       = aws_iam_role.web_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" 
}

resource "aws_iam_instance_profile" "web_instance_profile" {
  name = "web_instance_profile_${local.safe_user_name}"
  role = aws_iam_role.web_admin_role.name
}

resource "cloudflare_record" "site_dns" { 
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = aws_lb.app_alb.dns_name
  type    = "CNAME"
  proxied = true 
}

resource "cloudflare_record" "www_dns" { 
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = var.domain_name
  type    = "CNAME"
  proxied = true 
}

output "website_url" { value = "https://${var.domain_name}" }
output "load_balancer_dns_name" { value = aws_lb.app_alb.dns_name }