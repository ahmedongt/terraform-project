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
    # FIXED: Now matches the exact AMI prefix shown in your AWS console
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

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_traffic.id]
  }

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
  
  # Tells the ASG to scale across BOTH public subnets for high availability
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  
  # Hooks up the application pool to our load balancer target group
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_server.id
    version = "$Latest"
  }

  # Uses the ALB's active health checks rather than basic EC2 ping statuses
  health_check_type         = "ELB"
  health_check_grace_period = 300

  lifecycle {
    create_before_destroy = true
  }
}