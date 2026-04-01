# 0. THE DEFINITIONS
variable "cloudflare_api_token" {}
variable "cloudflare_zone_id" {}
variable "user_name" {}
variable "domain_name" {}
variable "instance_type" {}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "aws" {
  region = "us-east-1"
}

# 1. THE PERMANENT IP (ELASTIC IP)
resource "aws_eip" "web_eip" {
  instance = aws_instance.my_web_server.id
  domain   = "vpc"
}

# 2. THE FIREWALL
resource "aws_security_group" "web_traffic" {
  name        = "allow_web_api_and_ssh_cloudflare"
  description = "80 (HTTP), 5000 (API), 22 (SSH)"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. THE STORAGE BUCKET
resource "aws_s3_bucket" "website_bucket" {
  bucket        = "kali-web-lab-${lower(var.user_name)}-12345"
  force_destroy = true 
}

# 4. THE IDENTITY CARD
resource "aws_iam_role" "web_admin_role" {
  name = "web_admin_role_${var.user_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
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
        Action = ["s3:GetObject", "s3:ListBucket"]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.website_bucket.arn}",
          "${aws_s3_bucket.website_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "web_instance_profile" {
  name = "web_instance_profile_${var.user_name}"
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

              echo "--- STARTING PROVISIONING (CLOUDFLARE MODE) ---"
              dnf update -y
              dnf install -y nginx python3-pip aws-cli bind-utils

              mkdir -p /var/www/html

              # WAIT FOR S3 SYNC
              echo "Waiting for S3 sync to finish..."
              until [ -f "/var/www/html/api/app.py" ]; do
                aws s3 sync s3://${aws_s3_bucket.website_bucket.id} /var/www/html/
                echo "API folder not found yet. Sleeping 10s..."
                sleep 10
              done

              echo "Files synced. Setting permissions..."
              chown -R ec2-user:ec2-user /var/www/html
              chmod -R 755 /var/www/html

              # NGINX CONFIG (Simple Port 80 for Cloudflare Flexible SSL)
              rm -f /etc/nginx/conf.d/welcome.conf
              cat <<EOT > /etc/nginx/conf.d/flask.conf
              server {
                  listen 80;
                  server_name ${var.domain_name} www.${var.domain_name};
                  root /var/www/html;
                  index index.html;

                  location / {
                      try_files \$uri \$uri/ @flask;
                  }

                  location @flask {
                      proxy_pass http://127.0.0.1:5000;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                      proxy_set_header X-Forwarded-Proto \$scheme;
                  }
              }
              EOT

              systemctl enable nginx
              systemctl start nginx

              # PRODUCTION PYTHON SETUP
              echo "Installing Python dependencies system-wide..."
              sudo pip3 install flask flask-cors requests pillow gunicorn

              cd /var/www/html/api
              echo "Launching Gunicorn..."
              sudo pkill -f python3 || true
              sudo pkill -f gunicorn || true
              sudo nohup gunicorn --bind 127.0.0.1:5000 app:app > /var/log/flask.log 2>&1 &

              echo "--- PROVISIONING COMPLETE ---"
              EOF

  tags = { Name = "Web-Server-for-${var.user_name}" }
}

# 6. THE DNS BRIDGE (PROXIED BY CLOUDFLARE)
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