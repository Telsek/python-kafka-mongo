# existing hosted zone + wildcard cert from WeatherApp - looked up, never created or deleted
data "aws_route53_zone" "main" {
  name = var.domain
}

data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# the public front door, spread over both AZs
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# where the ALB sends traffic: the client containers (Fargate registers them by IP)
resource "aws_lb_target_group" "client" {
  name                 = "${var.project}-client"
  port                 = 8000
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 10 # faster deploys and destroys

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# port 80: send everyone to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# port 443: HTTPS with the wildcard cert, forward to the client
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.wildcard.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client.arn
  }
}

# shop.mansuraforecast.online -> the ALB (recreated every apply, removed on destroy)
resource "aws_route53_record" "shop" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.subdomain
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}