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
    dynamodb_table = "terraform-lock"
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
  cloudflare_ipv4 = jsondecode(data.http.cloudflare_ips.response_body).result.ipv4_cidrs
  safe_user_name  = lower(replace(var.user_name, " ", "-"))
}

# 1. THE PERMANENT IP (ELASTIC IP)
resource "aws_eip" "web_eip" {
  instance = aws_instance.my_web_server.id
  domain   = "vpc"
}

# 2. THE FIREWALL (HARDENED)
resource "aws_security_group" "web_traffic" {
  name        = "allow_web_api_and_ssh_cloudflare"
  description = "80/443 (Cloudflare), 5000 (API), 22 (SSH ONLY)"

  # HTTP/HTTPS: Only accessible through Cloudflare
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

  # API Access: Only accessible through Cloudflare
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  # SSH Access: REQUIRED for Tunneling to Grafana/Prometheus
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Change to your Home IP/32 for max security
  }

  # NOTE: Ports 3000 and 9090 are NOT listed here. 
  # They are closed to the public and only accessible via SSH Tunnel.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. THE STORAGE BUCKET
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${local.safe_user_name}-12345"
  force_destroy = true
}

# 4. THE IDENTITY CARD (IAM)
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
        Resource = ["${aws_s3_bucket.website_bucket.arn}", "${aws_s3_bucket.website_bucket.arn}/*"]
      },
      {
        Action   = ["ssm:UpdateInstanceInformation", "ssm:ListInstanceAssociations", "ssm:PutInventory"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
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
              usermod -a -G docker ec2-user
              ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
              ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
              mkdir -p /var/www/html
              aws s3 sync s3://${aws_s3_bucket.website_bucket.id}/ /var/www/html/
              cd /var/www/html/
              export DOCKER_BUILDKIT=1
              docker-compose up -d --build
              EOF

  tags = { Name = "Web-Server-for-${var.user_name}" }
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
output "website_url" {
  value = "https://${var.domain_name}"
}

output "server_ip" {
  value = aws_eip.web_eip.public_ip
}