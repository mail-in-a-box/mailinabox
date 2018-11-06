provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_ebs_volume" "miab_volume" {
    availability_zone = "${var.availability_zone}"
    size = 40
    tags {
        Name = "Mailinabox"
    }
    encrypted = true
}


resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id = "${aws_ebs_volume.miab_volume.id}"
  instance_id = "${aws_instance.web.id}"
}

resource "aws_instance" "web" {
  ami           = "ami-0927dc1f"

  # for 16.04
  # ami = "ami-f0768de6"

  instance_type = "t2.micro"

  subnet_id = "${aws_subnet.public_subnet_1.id}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.main_sg.id}"]
  key_name = "miab-key"

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "ubuntu"
      key_name = "miab-key"
    }
    inline = [
       "sudo apt-get update && curl -s https://mailinabox.email/setup.sh | sudo env NONINTERACTIVE=1 PRIMARY_HOSTNAME=${var.domain_name} PUBLIC_IP=${aws_instance.web.public_ip} PRIVATE_IP=${aws_instance.web.private_ip} STORAGE_USER=ubuntu STORAGE_ROOT=/home/ubuntu EMAIL_ADDR=${var.email_address} EMAIL_PW=${var.email_password} bash"
    ]
  }

}

output "public_ip_address" {
    value = "${aws_instance.web.public_ip}"
}
