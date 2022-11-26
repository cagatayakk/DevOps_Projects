data "aws_acm_certificate" "ssl-certificate" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

resource "aws_acm_certificate_validation" "cert_validation" {
  # provider = aws.acm_provider
  certificate_arn = data.aws_acm_certificate.ssl-certificate.arn
}
