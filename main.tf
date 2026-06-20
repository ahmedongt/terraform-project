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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "http" "cloudflare_ips" {
  url = "https://api.cloudflare.com/client/v4/ips"
}

data "aws_ami" "packer_golden_image" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["golden-devops-ami-al2023-*"]
  }
}

locals {
  cloudflare_ipv4   = jsondecode(data.http.cloudflare_ips.response_body).result.ipv4_cidrs
  safe_user_name    = lower(replace(var.user_name, " ", "-"))
  monitoring_bucket = "monitoring-configs-and-stats-kali"
}

# ====================================================================
# INDUSTRY STANDARD DECOUPLING: ECR IS NOW A READ-ONLY DATA DEPENDENCY
# ====================================================================
data "aws_ecr_repository" "devops_backend" {
  name = "devops-backend"
}

# ====================================================================
# CENTRALIZED STORAGE BUCKET
# ====================================================================
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${local.safe_user_name}-12345"
  force_destroy = true
}

# ====================================================================
# IAM PERMISSIONS TIER FOR AUTO SCALING INSTANCES
# ====================================================================
resource "aws_iam_role" "web_admin_role" {
  name = "web_admin_role_${local.safe_user_name}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "s3_and_ssm_access" {
  name = "s3_and_ssm_access"
  role = aws_iam_role.web_admin_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.website_bucket.arn}",
          "${aws_s3_bucket.website_bucket.arn}/*",
          "arn:aws:s3:::${local.monitoring_bucket}",
          "arn:aws:s3:::${local.monitoring_bucket}/*"
        ]
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

# ====================================================================
# CLOUDFLARE DNS ROUTING TRAFFIC EDGE TO APPLICATION LOAD BALANCER
# ====================================================================
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

# ====================================================================
# INFRASTRUCTURE OUTPUTS
# ====================================================================
output "monitoring_bucket_name" {
  value = local.monitoring_bucket
}

output "website_url" {
  value = "https://${var.domain_name}"
}

output "load_balancer_dns_name" {
  value       = aws_lb.app_alb.dns_name
  description = "Public entrypoint managed by the Application Load Balancer"
}