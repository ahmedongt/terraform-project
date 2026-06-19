# ====================================================================
# SECURITY GROUP FOR THE APPLICATION LOAD BALANCER
# ====================================================================
resource "aws_security_group" "alb_traffic" {
  name_prefix = "alb-traffic-cloudflare-"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Allows incoming traffic from Cloudflare to the ALB"

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

# ====================================================================
# DYNAMIC AMI LOOKUP (Fetches your latest build automatically)
# ====================================================================
data "aws_ami" "packer_app_ami" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["golden-devops-ami-al2023-*"] 
  }
}

# ====================================================================
# SECURITY GROUP FOR EC2 INSTANCES (Traffic isolation tier)
# ====================================================================
resource "aws_security_group" "ec2_traffic" {
  name_prefix = "ec2-traffic-from-alb-"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Allows incoming traffic only from the ALB"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_traffic.id]
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

# ====================================================================
# ASG LAUNCH TEMPLATE
# ====================================================================
resource "aws_launch_template" "app_server" {
  name_prefix   = "app-server-template-"
  image_id      = data.aws_ami.packer_app_ami.id
  instance_type = "t3.micro"
  key_name      = "Keypairforytthumbnail"

  # FIXED: Attaches the required IAM Profile for S3 and ECR authorization
  iam_instance_profile {
    name = aws_iam_instance_profile.web_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_traffic.id]
  }

  # FIXED: Converts standard heredoc text to base64 encoding for launch template compliance
  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e 
              
              # Log everything to user-data.log
              exec > >(tee /var/log/user-data.log) 2>&1
              
              echo "--- Starting ASG Dynamic Deployment ---"
              
              check_success() {
                  if [ $? -eq 0 ]; then
                      echo "SUCCESS: $1"
                  else
                      echo "ERROR: $1 failed!"
                      exit 1
                  fi
              }

              # 1. Setup Docker Compose
              mkdir -p /usr/local/lib/docker/cli-plugins
              curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
              chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
              ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/bin/docker-compose
              check_success "Docker Compose Installation"

              # 2. Fetch Payload
              TARGET_DIR="/app/terraform-project"
              rm -rf $TARGET_DIR
              mkdir -p $TARGET_DIR
              sleep 5
              aws s3 cp s3://${local.monitoring_bucket}/deployments/app-payload.tar.gz /tmp/app-payload.tar.gz
              tar -xzf /tmp/app-payload.tar.gz -C $TARGET_DIR/
              check_success "S3 Payload Download and Extraction"

              # 3. Generate Directories and Dashboards
              mkdir -p $TARGET_DIR/prometheus_data
              mkdir -p $TARGET_DIR/grafana_data
              aws s3 cp s3://${local.monitoring_bucket}/dashboards/node_exporter.json $TARGET_DIR/grafana/provisioning/dashboards/node_exporter.json

              # 4. Inject Variables Safely
              ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
              cat <<ENVEOF > $TARGET_DIR/.env
              GF_SECURITY_ADMIN_USER='${var.grafana_admin_user}'
              GF_SECURITY_ADMIN_PASSWORD='${var.grafana_admin_password}'
              AWS_ACCOUNT_ID='$ACCOUNT_ID'
              ENVEOF
              chmod 600 $TARGET_DIR/.env
              check_success ".env File Creation for Account $ACCOUNT_ID"

              # 5. Fix Permissions
              chown -R ec2-user:ec2-user $TARGET_DIR
              chmod 644 $TARGET_DIR/prometheus.yml || true
              chmod 644 $TARGET_DIR/default.conf || true
              
              chown -R 65534:65534 $TARGET_DIR/prometheus_data
              chown -R 472:472 $TARGET_DIR/grafana_data
              chmod -R 775 $TARGET_DIR/prometheus_data
              chmod -R 775 $TARGET_DIR/grafana_data

              # 6. Auth and Run
              cd $TARGET_DIR
              docker rm -f $(docker ps -aq) 2>/dev/null || true
              docker network prune -f || true
              
              aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
              check_success "ECR Authentication"
              
              docker-compose pull
              docker-compose up -d
              check_success "Container Orchestration"
              
              echo "--- ASG Managed Deployment Finished Successfully ---"
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-app-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ====================================================================
# AWS APPLICATION LOAD BALANCER (ALB)
# ====================================================================
resource "aws_lb" "app_alb" {
  name               = "custom-vpc-application-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_traffic.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "main-application-alb"
  }
}

# ====================================================================
# ALB TARGET GROUP
# ====================================================================
resource "aws_lb_target_group" "app_tg" {
  name     = "app-instances-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id

  health_check {
    enabled             = true
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# ====================================================================
# ALB LISTENER
# ====================================================================
resource "aws_lb_listener" "http_ingress" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ====================================================================
# AUTO SCALING GROUP (Ties the network, template, and ALB together)
# ====================================================================
resource "aws_autoscaling_group" "app_asg" {
  name_prefix         = "app-asg-"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_server.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  lifecycle {
    create_before_destroy = true
  }
}