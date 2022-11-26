output "websiteurl" {
  value = "http://${aws_lb.app-lb.dns_name}"
}

output "websiteurl-2" {
  value = "http://www.${var.domain_name}"
}
