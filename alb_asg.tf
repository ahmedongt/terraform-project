# ====================================================================
# NEW SECURITY GROUP FOR THE APPLICATION LOAD BALANCER
# ====================================================================
resource "aws_security_group" "alb_traffic" {
  name_prefix = "alb-traffic-cloudflare-"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Allows incoming traffic from Cloudflare to the ALB"

  # Accept HTTP traffic from Cloudflare proxies
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  # Accept HTTPS traffic from Cloudflare proxies
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.cloudflare_ipv4
  }

  # Allow the ALB to send health checks and traffic out to the EC2 instances
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