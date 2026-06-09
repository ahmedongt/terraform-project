# ==========================================
# FILE: main.tf (Production Automated Zero-Touch Deployment)
# ==========================================

variable "cloudflare_api_token" {}
variable "cloudflare_zone_id" {}
variable "user_name" {}
variable "domain_name" {}
variable "instance_type" {}
variable "grafana_admin_user" { type = string; sensitive = true }
variable "grafana_admin_password" { type = string; sensitive = true }

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

data "aws_caller_identity" "current" {}
data "http" "cloudflare_ips" { url = "https://api.cloudflare.com/client/v4/ips" }

data "aws_ami" "packer_golden_image" {
  most_recent = true
  owners      = ["self"]
  filter { name = "name"; values = ["golden-devops-ami-al2023-*"] }
}

locals {
  cloudflare_ipv4   = jsondecode(data.http.cloudflare_ips.response_body).result.ipv4_cidrs
  safe_user_name    = lower(replace(var.user_name, " ", "-"))
  monitoring_bucket = "monitoring-configs-and-stats-kali"
}

resource "aws_ecr_repository" "devops_backend" {
  name                 = "devops-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_security_group" "web_traffic" {
  name_prefix = "allow_web_api_cloudflare-" 
  description = "Managed reverse proxy entry points - 80/443 (Cloudflare), 5000 (API)"
  vpc_id      = aws_vpc.main.id # CONNECTED TO VPC

  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = local.cloudflare_ipv4 }
  ingress { from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = local.cloudflare_ipv4 }
  ingress { from_port = 5000; to_port = 5000; protocol = "tcp"; cidr_blocks = local.cloudflare_ipv4 }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_eip" "web_eip" {
  domain   = "vpc"
  instance = aws_instance.my_web_server.id
  depends_on = [aws_internet_gateway.igw] # Ensure IGW exists first
}

resource "aws_s3_bucket" "website_bucket" { bucket = "kali-web-lab-${local.safe_user_name}-12345"; force_destroy = true }

resource "aws_iam_role" "web_admin_role" {
  name = "web_admin_role_${local.safe_user_name}"
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
    Statement = [{
      Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
      Effect = "Allow"
      Resource = ["${aws_s3_bucket.website_bucket.arn}", "${aws_s3_bucket.website_bucket.arn}/*", "arn:aws:s3:::${local.monitoring_bucket}", "arn:aws:s3:::${local.monitoring_bucket}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" { role = aws_iam_role.web_admin_role.name; policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
resource "aws_iam_role_policy_attachment" "ecr_readonly_attach" { role = aws_iam_role.web_admin_role.name; policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" }
resource "aws_iam_instance_profile" "web_instance_profile" { name = "web_instance_profile_${local.safe_user_name}"; role = aws_iam_role.web_admin_role.name }

resource "aws_instance" "my_web_server" {
  ami                         = data.aws_ami.packer_golden_image.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1.id # PLACED IN PUBLIC SUBNET
  vpc_security_group_ids      = [aws_security_group.web_traffic.id]
  iam_instance_profile        = aws_iam_instance_profile.web_instance_profile.name
  key_name                    = "Keypairforytthumbnail"
  user_data_replace_on_change = true

  # (Keep your entire existing user_data block here)
  user_data = <<-EOF
              #!/bin/bash
              # ... [YOUR EXISTING USER DATA]
              EOF

  tags = { Name = "Web-Server-for-${var.user_name}" }
}

resource "cloudflare_record" "site_dns" { zone_id = var.cloudflare_zone_id; name = "@"; content = aws_eip.web_eip.public_ip; type = "A"; proxied = true }
resource "cloudflare_record" "www_dns" { zone_id = var.cloudflare_zone_id; name = "www"; content = var.domain_name; type = "CNAME"; proxied = true }

output "website_url" { value = "https://${var.domain_name}" }
output "server_ip" { value = aws_eip.web_eip.public_ip }