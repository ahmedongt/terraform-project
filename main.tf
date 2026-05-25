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
  # Switched to name_prefix to avoid duplicate naming deadlocks during creation
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

# 5. THE SERVER (100% FULLY AUTOMATED CONTAINER STACK DEPLOYMENT)
resource "aws_instance" "my_web_server" {
  ami                         = "ami-022a61cddf3a30415"
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web_traffic.id]
  iam_instance_profile        = aws_iam_instance_profile.web_instance_profile.name
  key_name                    = "Keypairforytthumbnail"
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              echo "=== Executing Custom Application Runtime Handlers ==="
              
              # 1. Automate Workspace Generation
              mkdir -p /home/ec2-user/terraform-project
              cd /home/ec2-user/terraform-project

              # 2. Automate Docker Compose File Creation Hands-Free
              cat << 'COMPOSE_EOF' > docker-compose.yml
              services:
                grafana:
                  image: grafana/grafana-oss:latest
                  container_name: grafana
                  ports:
                    - "3000:3000"
                  volumes:
                    - grafana_data:/var/lib/grafana
                  restart: unless-stopped

              volumes:
                grafana_data:
                  name: terraform-project_grafana_data
COMPOSE_EOF

              # 3. Fire up the App Architecture instantly on boot
              docker-compose up -d

              # 4. Drop the Self-Healing Data Restoration Script onto the file system
              cat << 'SCRIPT' > /usr/local/bin/grafana-volume-heal.sh
              #!/bin/bash
              TARGET_DIR="/var/lib/docker/volumes/terraform-project_grafana_data/_data"
              
              for i in {1..60}; do
                  if [ -d "$TARGET_DIR" ]; then
                      echo "Docker volume storage path located. Attempting secure data state extraction..."
                      
                      if aws s3 cp s3://${local.monitoring_bucket}/backups/monitoring_state_2026-05-19_03-00.tar.gz /tmp/monitoring_state.tar.gz; then
                          echo "Backup metadata tarball downloaded successfully from S3."
                          
                          docker stop grafana || true
                          rm -rf "$TARGET_DIR"/*
                          tar -xzf /tmp/monitoring_state.tar.gz --strip-components=2 -C "$TARGET_DIR/"
                          
                          echo "Enforcing strict user 472 ownership across data tree components..."
                          chown -R 472:472 /var/lib/docker/volumes/terraform-project_grafana_data
                          chmod -R 775 /var/lib/docker/volumes/terraform-project_grafana_data
                          
                          if [ -f "$TARGET_DIR/grafana.db" ]; then
                              chmod 664 "$TARGET_DIR/grafana.db"
                              chown 472:472 "$TARGET_DIR/grafana.db"
                          fi
                          
                          docker start grafana || true
                          sleep 5
                          echo "Performing cache clearing double-bounce power cycle..."
                          docker restart grafana || true
                          
                          echo "Infrastructure metrics storage state successfully healed!"
                          break
                      else
                          echo "AWS IAM profile evaluation or networking not ready yet. Retrying in 10 seconds..."
                      fi
                  fi
                  sleep 10
              done
SCRIPT

              chmod +x /usr/local/bin/grafana-volume-heal.sh
              
              # 5. Launch the background healer thread asynchronously
              /usr/local/bin/grafana-volume-heal.sh > /var/log/grafana-healer.log 2>&1 &
              
              echo "=== Run-time Orchestration Initialization Complete ==="
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
  value = local.monitoring_bucket
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