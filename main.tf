# 0. THE DEFINITIONS      
variable "cloudflare_api_token" {}
variable "cloudflare_zone_id" {}
variable "user_name" {}
variable "domain_name" {}
variable "instance_type" {}

terraform {
  backend "s3" {
    bucket         = "kali-terraform-state-storage-2026"
    key            = "state/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "kali-terraform-state-locks" # Links your permanent locking table!
    use_lockfile   = true 
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

locals {
  cloudflare_ipv4   = jsondecode(data.http.cloudflare_ips.response_body).result.ipv4_cidrs
  safe_user_name    = lower(replace(var.user_name, " ", "-"))
  monitoring_bucket = "monitoring-configs-and-stats-kali"
}

# 1. THE PERMANENT IP (ELASTIC IP)
resource "aws_eip" "web_eip" {
  instance = aws_instance.my_web_server.id
  domain   = "vpc"

  # Prevents EIP from blocking the instance recreation lifecycle
  lifecycle {
    create_before_destroy = true
  }
}

# 2. THE FIREWALL (HARDENED - PORT 22 REMOVED FROM PUBLIC INTERNET)
resource "aws_security_group" "web_traffic" {
  # CHANGED: Switched to name_prefix to avoid duplicate naming deadlocks during creation
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

  # Creates the new security group rules before ripping out the old ones
  lifecycle {
    create_before_destroy = true
  }
}

# 3. THE STORAGE BUCKETS
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${local.safe_user_name}-12345"
  force_destroy = true
}

# 4. THE IDENTITY CARD (IAM ROLE & SYSTEMS MANAGER POLICIES)
resource "aws_iam_role" "web_admin_role" {
  name = "web_admin_role_${local.safe_user_name}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# Custom Policy for S3 access
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
      }
    ]
  })
}

# Attach Official AWS Systems Manager Policy to allow secure SSH-less connectivity
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
  ami                         = "ami-05b10e08d247fb927"
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web_traffic.id]
  iam_instance_profile        = aws_iam_instance_profile.web_instance_profile.name
  key_name                    = "Keypairforytthumbnail"
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              dnf update -y
              dnf install -y docker aws-cli
              dnf install -y docker-buildx-plugin docker-compose-plugin
              systemctl start docker
              systemctl enable docker
              
              # Fix: Pre-create ssm-user and grant root-less docker permissions out of the gate
              usermod -a -G docker ec2-user
              useradd -m ssm-user
              usermod -a -G docker ssm-user
              
              ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
              ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
              mkdir -p /var/www/html

              # --- FIXED PERSISTENT MONITORING DATA RECOVERY ---
              # Pre-build the named docker volume directory structure matching your compose environment
              mkdir -p /var/lib/docker/volumes/terraform-project_grafana_data/_data

              # Copy backup compression stack from target S3 metrics vault
              echo "Pulling down persistent monitoring state archive from S3..."
              aws s3 cp s3://${local.monitoring_bucket}/monitoring_state.tar.gz /tmp/monitoring_state.tar.gz
              
              if [ -f /tmp/monitoring_state.tar.gz ]; then
                  echo "Extracting backup payload directly into named Docker volume storage..."
                  # Strips the wrapper layer from the archive and extracts contents cleanly into the volume root
                  tar -xzf /tmp/monitoring_state.tar.gz --strip-components=1 -C /var/lib/docker/volumes/terraform-project_grafana_data/_data/
              fi

              echo "Enforcing strict read/write permissions on restored monitoring assets..."
              # 1. Ensure the volume directory root is completely readable and writable
              chmod -R 777 /var/lib/docker/volumes/terraform-project_grafana_data/_data

              # 2. Fix the SQLite database permissions explicitly if it extracted successfully
              if [ -f /var/lib/docker/volumes/terraform-project_grafana_data/_data/grafana.db ]; then
                  chmod 664 /var/lib/docker/volumes/terraform-project_grafana_data/_data/grafana.db
              fi

              # 3. Force inner Grafana user (UID 472) ownership across the unpacked directory structural tree
              chown -R 472:472 /var/lib/docker/volumes/terraform-project_grafana_data/_data
              EOF

  tags = { Name = "Web-Server-for-${var.user_name}" }

  # Spins up the new virtual machine before terminating the old one
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
  value = local.monitoring_bucket
}

output "website_url" {
  value = "https://${var.domain_name}"
}

output "server_ip" {
  value = aws_eip.web_eip.public_ip
}

# Dynamic Output required by the GitHub Actions automated SSM Proxy Runner
output "ec2_instance_id" {
  value       = aws_instance.my_web_server.id
  description = "The target AWS Instance ID for Session Manager mapping"
}