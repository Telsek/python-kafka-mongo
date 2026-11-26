output "shop_url" {
  description = "Open this in the browser"
  value       = "https://${aws_route53_record.shop.fqdn}"
}

output "alb_dns" {
  description = "Raw ALB address (the shop URL points here)"
  value       = aws_lb.main.dns_name
}

output "logs" {
  description = "CloudWatch log group with all container logs"
  value       = aws_cloudwatch_log_group.main.name
}