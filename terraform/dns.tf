# Create a record
resource "aws_route53_zone" "main" {
   name = "${var.domain_name}"
}

resource "aws_route53_record" "root_record" {
   zone_id = "${aws_route53_zone.main.zone_id}"
   name = ""
   type = "A"
   ttl = 300
   records = ["${aws_instance.web.public_ip}"]
}

resource "aws_route53_record" "www" {
   zone_id = "${aws_route53_zone.main.zone_id}"
   name = "www"
   type = "A"
   ttl = 300
   records = ["${aws_instance.web.public_ip}"]
}
