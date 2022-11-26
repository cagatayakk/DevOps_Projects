output "websiteurl" {
  value = "http://${aws_lb.app-lb.dns_name}"
}
