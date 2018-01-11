terraform {
  required_version = "> 0.11.0"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

resource "random_id" "national_parks_id" {
  byte_length = 4
}

////////////////////////////////
// Firewalls

resource "aws_security_group" "national-parks" {
  name        = "national-parks"
  description = "National Parks"
  vpc_id      = "${var.aws_vpc_id}"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9631
    to_port     = 9631
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9638
    to_port     = 9638
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9631
    to_port     = 9631
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9638
    to_port     = 9638
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    X-Contact     = "The Example Maintainer <maintainer@example.com>"
    X-Application = "national-parks"
    X-ManagedBy   = "Terraform"
  }
}

////////////////////////////////
// Initial Peer

data "aws_subnet_ids" "national-parks" {
  vpc_id = "${var.aws_vpc_id}"
}

data "aws_ami" "centos" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"] # centos.org
}


resource "aws_instance" "initial-peer" {
  connection {
    user        = "${var.aws_image_user}"
    private_key = "${file("${var.aws_key_pair_file}")}"
  }

  ami                         = "${data.aws_ami.centos.id}"
  instance_type               = "m4.large"
  key_name                    = "${var.aws_key_pair_name}"
  subnet_id                   = "${data.aws_subnet_ids.national-parks.ids[1]}"
  vpc_security_group_ids      = ["${aws_security_group.national-parks.id}"]
  associate_public_ip_address = true

  tags {
    Name      = "national_parks_${random_id.national_parks_id.hex}_initial_peer"
    X-Dept    = "SCE"
    X-Contact = "echohack"
  }

  # Set hostname in separate connection.
  # Transient hostname doesn't set correctly in time otherwise.
  provisioner "remote-exec" {
    inline = ["sudo hostnamectl set-hostname ${aws_instance.initial-peer.public_dns}"]
  }

  provisioner "file" {
    content     = "${data.template_file.install_hab.rendered}"
    destination = "/tmp/install_hab.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.initial_peer.rendered}"
    destination = "/home/${var.aws_image_user}/hab-sup.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo adduser --group hab",
      "sudo useradd -g hab hab",
      "chmod +x /tmp/install_hab.sh",
      "sudo /tmp/install_hab.sh",
      "sudo mv /home/${var.aws_image_user}/hab-sup.service /etc/systemd/system/hab-sup.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl start hab-sup",
      "sudo systemctl enable hab-sup",
    ]
  }
}


////////////////////////////////
// Instances

resource "aws_instance" "np-mongodb" {
  connection {
    user        = "${var.aws_image_user}"
    private_key = "${file("${var.aws_key_pair_file}")}"
  }

  ami                         = "${data.aws_ami.centos.id}"
  instance_type               = "m4.large"
  key_name                    = "${var.aws_key_pair_name}"
  subnet_id                   = "${data.aws_subnet_ids.national-parks.ids[1]}"
  vpc_security_group_ids      = ["${aws_security_group.national-parks.id}"]
  associate_public_ip_address = true

  tags {
    Name      = "national_parks_${random_id.national_parks_id.hex}_np_mongodb"
    X-Dept    = "SCE"
    X-Contact = "echohack"
  }

  # Set hostname in separate connection.
  # Transient hostname doesn't set correctly in time otherwise.
  provisioner "remote-exec" {
    inline = ["sudo hostnamectl set-hostname ${aws_instance.initial-peer.public_dns}"]
  }

  provisioner "file" {
    content     = "${data.template_file.install_hab.rendered}"
    destination = "/tmp/install_hab.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.sup_service.rendered}"
    destination = "/home/${var.aws_image_user}/hab-sup.service"
  }

  provisioner "local-exec" {
    command = "scp -oStrictHostKeyChecking=no -i ${var.aws_key_pair_file} ${var.local_hart_dir}/${var.np_mongodb_hart} ${var.aws_image_user}@${self.public_ip}:/home/${var.aws_image_user}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo adduser --group hab",
      "sudo useradd -g hab hab",
      "chmod +x /tmp/install_hab.sh",
      "sudo /tmp/install_hab.sh",
      "sudo mv /home/${var.aws_image_user}/hab-sup.service /etc/systemd/system/hab-sup.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl start hab-sup",
      "sudo systemctl enable hab-sup",
      "sudo hab pkg install /home/${var.aws_image_user}/${var.np_mongodb_hart}",
      "sudo hab svc load echohack/np-mongodb --group prod --strategy at-once",
    ]
  }
}

resource "aws_instance" "np-mongodb" {
  connection {
    user        = "${var.aws_image_user}"
    private_key = "${file("${var.aws_key_pair_file}")}"
  }

  ami                         = "${data.aws_ami.centos.id}"
  instance_type               = "m4.large"
  key_name                    = "${var.aws_key_pair_name}"
  subnet_id                   = "${data.aws_subnet_ids.national-parks.ids[1]}"
  vpc_security_group_ids      = ["${aws_security_group.national-parks.id}"]
  associate_public_ip_address = true

  tags {
    Name      = "national_parks_${random_id.national_parks_id.hex}_np_mongodb"
    X-Dept    = "SCE"
    X-Contact = "echohack"
  }

  # Set hostname in separate connection.
  # Transient hostname doesn't set correctly in time otherwise.
  provisioner "remote-exec" {
    inline = ["sudo hostnamectl set-hostname ${aws_instance.initial-peer.public_dns}"]
  }

  provisioner "file" {
    content     = "${data.template_file.install_hab.rendered}"
    destination = "/tmp/install_hab.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.sup_service.rendered}"
    destination = "/home/${var.aws_image_user}/hab-sup.service"
  }

  provisioner "local-exec" {
    command = "scp -oStrictHostKeyChecking=no -i ${var.aws_key_pair_file} ${var.local_hart_dir}/${var.national_parks_hart} ${var.aws_image_user}@${self.public_ip}:/home/${var.aws_image_user}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo adduser --group hab",
      "sudo useradd -g hab hab",
      "chmod +x /tmp/install_hab.sh",
      "sudo /tmp/install_hab.sh",
      "sudo mv /home/${var.aws_image_user}/hab-sup.service /etc/systemd/system/hab-sup.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl start hab-sup",
      "sudo systemctl enable hab-sup",
      "sudo hab pkg install /home/${var.aws_image_user}/${var.national_parks_hart}",
      "sudo hab svc load echohack/national-parks --group prod --bind database:np-mongodb.prod --strategy at-once",
    ]
  }
}

////////////////////////////////
// Templates

data "template_file" "initial_peer" {
  template = "${file("${path.module}/../templates/hab-sup.service")}"

  vars {
    flags = "--auto-update --listen-gossip 0.0.0.0:9638 --listen-http 0.0.0.0:9631 --permanent-peer"
  }
}

data "template_file" "sup_service" {
  template = "${file("${path.module}/../templates/hab-sup.service")}"

  vars {
    flags = "--auto-update --peer ${aws_instance.initial-peer.private_ip} --listen-gossip 0.0.0.0:9638 --listen-http 0.0.0.0:9631"
  }
}

data "template_file" "install_hab" {
  template = "${file("${path.module}/../templates/install-hab.sh")}"
}
