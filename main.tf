# ==========================================
# FILE: main.tf (Validated Platform Infrastructure & Fixed Mount Paths)
# ==========================================

variable "cloudflare_api_token" {}
variable "cloudflare_zone_id" {}
variable "user_name" {}
variable "domain_name" {}
variable "instance_type" {}

# SECURE INJECTED VARIABLES FROM GITHUB RUNNER
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

# --- AUTOMATED CLOUDFLARE IP FETCHING ---
data "http" "cloudflare_ips" {
  url = "https://api.cloudflare.com/client/v4/ips"
}

# --- DYNAMICALLY LOCATE THE LATEST PACKER GOLDEN IMAGE ---
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

# 1. THE PERMANENT IP (ELASTIC IP)
resource "aws_eip" "web_eip" {
  instance = aws_instance.my_web_server.id
  domain   = "vpc"

  lifecycle {
    create_before_destroy = true
  }
}

# 2. THE FIREWALL
resource "aws_security_group" "web_traffic" {
  name_prefix = "allow_web_api_cloudflare-" 
  description = "80/443 (Cloudflare), 5000 (API) - PORT 22 STRIPPED FOR SSM SECURE PROXY"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 3. THE STORAGE BUCKETS
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${local.safe_user_name}-12345"
  force_destroy = true
}

resource "aws_s3_bucket" "monitoring_storage" {
  bucket        = local.monitoring_bucket
  force_destroy = false 
}

# Uploads Dashboard to S3 Bucket securely
resource "aws_s3_object" "grafana_dashboard" {
  bucket = aws_s3_bucket.monitoring_storage.id
  key    = "dashboards/node_exporter.json"
  source = "${path.module}/grafana/provisioning/dashboards/node_exporter.json"
  etag   = filemd5("${path.module}/grafana/provisioning/dashboards/node_exporter.json")
}

# 4. THE IDENTITY CARD
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
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.website_bucket.arn}", 
          "${aws_s3_bucket.website_bucket.arn}/*",
          "${aws_s3_bucket.monitoring_storage.arn}",
          "${aws_s3_bucket.monitoring_storage.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.web_admin_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web_instance_profile" {
  name = "web_instance_profile_${local.safe_user_name}"
  role = aws_iam_role.web_admin_role.name
}

# 5. THE SERVER
resource "aws_instance" "my_web_server" {
  ami                         = data.aws_ami.packer_golden_image.id
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web_traffic.id]
  iam_instance_profile        = aws_iam_instance_profile.web_instance_profile.name
  key_name                    = "Keypairforytthumbnail"
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              # Route runtime standard output tracking securely to system logs
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
               
              echo "=== Verifying and Ensuring Standalone Docker Compose Subsystem ==="
              mkdir -p /usr/local/lib/docker/cli-plugins
              curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
              chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
              ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/bin/docker-compose

              echo "=== Initializing Production Workspace Targets ==="
              TARGET_DIR="/app/terraform-project"
              mkdir -p $TARGET_DIR/prometheus_data
              mkdir -p $TARGET_DIR/grafana_data
              mkdir -p $TARGET_DIR/grafana/provisioning/dashboards
              mkdir -p $TARGET_DIR/grafana/provisioning/datasources

              echo "=== Injecting Core Secure Environment Variables ==="
              cat <<ENVEOF > $TARGET_DIR/.env
              GF_SECURITY_ADMIN_USER='${var.grafana_admin_user}'
              GF_SECURITY_ADMIN_PASSWORD='${var.grafana_admin_password}'
              ENVEOF
              chmod 600 $TARGET_DIR/.env

              echo "=== Fetching Dynamic Configuration Map Components ==="
              # Fetch matching dashboard json from tracking S3 architecture bucket
              aws s3 cp s3://${local.monitoring_bucket}/dashboards/node_exporter.json $TARGET_DIR/grafana/provisioning/dashboards/node_exporter.json

              echo "=== Applying Rigid Storage Permission Policies ==="
              # Fix host file locks explicitly before firing up the engines
              chown -R 65534:65534 $TARGET_DIR/prometheus_data
              chown -R 472:472 $TARGET_DIR/grafana_data
              chmod -R 775 $TARGET_DIR/prometheus_data
              chmod -R 775 $TARGET_DIR/grafana_data

              # Grant deployment execution scope mapping permissions to default user profiles
              chown -R ec2-user:ec2-user $TARGET_DIR
              
              echo "=== Initializing Execution Orchestration Layer ==="
              cd $TARGET_DIR
              
              # Force clear any background ghosts left on snapshot snapshots cleanly
              docker rm -f $(docker ps -aq) 2>/dev/null || true
              docker network prune -f || true

              # Fire the production engine tracks down and up completely hands-free
              docker-compose down --remove-orphans || true
              docker-compose up -d
               
              echo "=== System Deployment Engine Tasks Complete ==="
              EOF

  tags = { Name = "Web-Server-for-${var.user_name}" }

  lifecycle {
    create_before_destroy = true
  }
}

# 6. THE DNS BRIDGE
resource "cloudflare_record" "site_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = aws_eip.web_eip.public_ip
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "www_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = var.domain_name 
  type    = "CNAME"         
  proxied = true
}

# 7. OUTPUTS
output "monitoring_bucket_name" {
  value = aws_s3_bucket.monitoring_storage.id
}

output "website_url" {
  value = "https://${var.domain_name}"
}

output "server_ip" {
  value = aws_eip.web_eip.public_ip
}

output "ec2_instance_id" {
  value       = aws_instance.my_web_server.id
  description = "The target AWS Instance ID for Session Manager mapping"
}