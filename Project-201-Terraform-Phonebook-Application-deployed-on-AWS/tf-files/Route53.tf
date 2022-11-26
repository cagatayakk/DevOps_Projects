data "aws_route53_zone" "my-hosted-zone" {
  name         = var.domain_name
}

resource "aws_route53_record" "Arecord" {
  allow_overwrite = true
  zone_id = data.aws_route53_zone.my-hosted-zone.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.app-lb.dns_name
    zone_id                = aws_lb.app-lb.zone_id
    evaluate_target_health = true
  }
}
