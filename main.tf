# ==========================================
# FILE: main.tf (Modernized Platform Configuration)
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

# 2. THE FIREWALL (PORT 22 STRIPPED FOR SSM SECURE PROXY)
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

# PERSISTENT STORAGE LOCK (Survives infrastructure destruction loops)
resource "aws_s3_bucket" "monitoring_storage" {
  bucket        = local.monitoring_bucket
  force_destroy = false 
}

# 4. THE IDENTITY CARD (IAM ROLE & SYSTEMS MANAGER POLICIES)
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

# 5. THE SERVER (BACKED BY HYBRID DYNAMIC CONFIGURATION)
resource "aws_instance" "my_web_server" {
  ami                         = data.aws_ami.packer_golden_image.id
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.web_traffic.id]
  iam_instance_profile        = aws_iam_instance_profile.web_instance_profile.name
  key_name                    = "Keypairforytthumbnail"
  user_data_replace_on_change = true

  # COMPOSING DYNAMIC CONFIGURATIONS AND THE DOCKER ENGINE AT RUNTIME
  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              echo "=== Downloading Standalone Docker Compose Engine Subsystem ==="
              mkdir -p /usr/local/lib/docker/cli-plugins
              curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
              chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

              # Create a global fallback symlink so both 'docker compose' and old 'docker-compose' work seamlessly
              ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/bin/docker-compose

              echo "=== Creating Project Directories ==="
              mkdir -p /app/terraform-project/prometheus_data
              mkdir -p /app/terraform-project/grafana_data
              mkdir -p /app/terraform-project/grafana/provisioning/dashboards
              mkdir -p /app/terraform-project/grafana/provisioning/datasources

              echo "=== Injecting Secure Environment Secrets ==="
              cat <<ENVEOF > /app/terraform-project/.env
              GF_SECURITY_ADMIN_USER='${var.grafana_admin_user}'
              GF_SECURITY_ADMIN_PASSWORD='${var.grafana_admin_password}'
              ENVEOF
              chmod 600 /app/terraform-project/.env

              echo "=== Dynamically Generating Provisioning Infrastructure ==="
              
              # 1. Inject Grafana Dashboard Config Provider
              cat << 'DASHBOARD_EOF' > /app/terraform-project/grafana/provisioning/dashboards/all.yml
              apiVersion: 1
              providers:
                - name: 'default'
                  orgId: 1
                  folder: ''
                  type: file
                  disableDeletion: false
                  editable: true
                  options:
                    path: /var/lib/grafana/dashboards
              DASHBOARD_EOF

              # 2. Inject Grafana Prometheus Data Source Configuration
              cat << 'DATASOURCE_EOF' > /app/terraform-project/grafana/provisioning/datasources/prometheus.yml
              apiVersion: 1
              datasources:
                - name: Prometheus
                  type: prometheus
                  access: proxy
                  url: http://prometheus:9090
                  isDefault: true
              DATASOURCE_EOF

              # 3. Inject Your Node Exporter Dashboard JSON File 
              cat << 'JSON_EOF' > /app/terraform-project/grafana/provisioning/dashboards/node_exporter.json
              {
                "annotations": { "list": [] },
                "editable": true,
                "fiscalYearStartMonth": 0,
                "graphTooltip": 0,
                "id": null,
                "links": [],
                "liveNow": false,
                "panels": [],
                "refresh": "5s",
                "schemaVersion": 38,
                "style": "dark",
                "tags": [],
                "time": { "from": "now-1h", "to": "now" },
                "timepicker": {},
                "timezone": "",
                "title": "Node Exporter Dashboard",
                "version": 1,
                "weekStart": ""
              }
              JSON_EOF

              # 4. Inject Dynamic Base Prometheus Config File
              cat << 'PROM_EOF' > /app/terraform-project/prometheus.yml
              global:
                scrape_interval: 15s
              scrape_configs:
                - job_name: 'prometheus'
                  static_configs:
                    - targets: ['localhost:9090']
                - job_name: 'node-exporter'
                  static_configs:
                    - targets: ['node-exporter:9100']
              PROM_EOF

              # 5. Inject Your Production Docker Compose Setup File Natively
              cat << 'COMPOSE_EOF' > /app/terraform-project/docker-compose.yml
              version: '3.8'
              services:
                backend:
                  image: devops-backend:latest
                  container_name: backend
                  restart: unless-stopped
                  expose:
                    - "5000"

                frontend:
                  image: nginx:alpine
                  container_name: frontend
                  restart: unless-stopped
                  ports:
                    - "80:80"
                  depends_on:
                    - backend

                node-exporter:
                  image: prom/node-exporter:latest
                  container_name: node-exporter
                  restart: unless-stopped
                  volumes:
                    - /proc:/host/proc:ro
                    - /sys:/host/sys:ro
                    - /:/rootfs:ro
                  command:
                    - '--path.procfs=/host/proc'
                    - '--path.rootfs=/rootfs'
                    - '--path.sysfs=/host/sys'

                prometheus-init:
                  image: alpine:latest
                  container_name: prometheus-init
                  user: "root"
                  volumes:
                    - ./prometheus_data:/prometheus
                  command: chown -R 65534:65534 /prometheus

                prometheus:
                  image: prom/prometheus:latest
                  container_name: prometheus
                  restart: unless-stopped
                  ports:
                    - "9090:9090"
                  volumes:
                    - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
                    - ./prometheus_data:/prometheus
                  command:
                    - '--config.file=/etc/prometheus/prometheus.yml'
                    - '--storage.tsdb.retention.time=15d'
                    - '--storage.tsdb.path=/prometheus'
                    - '--web.enable-admin-api'
                  depends_on:
                    backend:
                      condition: service_started
                    node-exporter:
                      condition: service_started
                    prometheus-init:
                      condition: service_completed_successfully

                grafana-init:
                  image: alpine:latest
                  container_name: grafana-init
                  user: "root"
                  volumes:
                    - ./grafana_data:/var/lib/grafana
                  command: chown -R 472:472 /var/lib/grafana

                grafana:
                  image: grafana/grafana:latest
                  container_name: grafana
                  restart: unless-stopped
                  ports:
                    - "3000:3000"
                  environment:
                    - GF_SECURITY_ADMIN_USER=$${GF_SECURITY_ADMIN_USER}
                    - GF_SECURITY_ADMIN_PASSWORD=$${GF_SECURITY_ADMIN_PASSWORD}
                  volumes:
                    - ./grafana_data:/var/lib/grafana
                    - ./grafana/provisioning:/etc/grafana/provisioning:ro
                  depends_on:
                    prometheus:
                      condition: service_started
                    grafana-init:
                      condition: service_completed_successfully
              COMPOSE_EOF

              echo "=== Configuring Folder Permissions ==="
              chown -R ec2-user:ec2-user /app/terraform-project
              chmod -R 755 /app/terraform-project

              echo "=== Initializing Application Engine Core Orchestration ==="
              cd /app/terraform-project
              
              /usr/local/lib/docker/cli-plugins/docker-compose down || true
              /usr/local/lib/docker/cli-plugins/docker-compose up -d
              
              echo "=== Deployment Completed Safely ==="
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