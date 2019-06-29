locals {
  tags = {
    application = "poc-ec2-database"
    owner       = "terraform"
  }

  main_vpc_cidr_block_prefix = "180.31"

  region = "eu-central-1"
}

provider "aws" {
  region = "${local.region}"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main_vpc" {
  cidr_block           = "${local.main_vpc_cidr_block_prefix}.0.0/16"
  enable_dns_hostnames = "true"

  tags = "${local.tags}"
}

resource "aws_subnet" "main_vpc_subnet_1" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  cidr_block        = "${local.main_vpc_cidr_block_prefix}.${0 * 16}.0/20"
  availability_zone = "${element(data.aws_availability_zones.available.names, 0)}"

  tags = "${local.tags}"
}

resource "aws_subnet" "main_vpc_subnet_2" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  cidr_block        = "${local.main_vpc_cidr_block_prefix}.${1 * 16}.0/20"
  availability_zone = "${element(data.aws_availability_zones.available.names, 1)}"

  tags = "${local.tags}"
}

resource "aws_subnet" "main_vpc_subnet_3" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  cidr_block        = "${local.main_vpc_cidr_block_prefix}.${2 * 16}.0/20"
  availability_zone = "${element(data.aws_availability_zones.available.names, 2)}"

  tags = "${local.tags}"
}

resource "aws_internet_gateway" "main_vpc_internet_gateway" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  tags = "${local.tags}"
}

resource "aws_route_table" "main_vpc_route_table" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.main_vpc_internet_gateway.id}"
  }

  tags = "${local.tags}"
}

resource "aws_route_table_association" "main_vpc_route_table_association_1" {
  subnet_id      = "${aws_subnet.main_vpc_subnet_1.id}"
  route_table_id = "${aws_route_table.main_vpc_route_table.id}"
}

resource "aws_security_group" "main_security_group" {
  name = "Main Security group"

  vpc_id = "${aws_vpc.main_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${local.tags}"
}

resource "aws_security_group_rule" "ssh_sg_rule" {
  type              = "ingress"
  from_port         = "22"
  to_port           = "22"
  cidr_blocks       = ["78.193.217.31/32", "92.154.181.233/32"]
  protocol          = "tcp"
  security_group_id = "${aws_security_group.main_security_group.id}"
  description       = "Connection from local machine"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "database_host" {
  ami                         = "${data.aws_ami.ubuntu.id}"
  instance_type               = "t2.micro"
  key_name                    = "isnan_mac"
  subnet_id                   = "${aws_subnet.main_vpc_subnet_1.id}"
  vpc_security_group_ids      = ["${aws_security_group.main_security_group.id}"]
  associate_public_ip_address = true

  // iam_instance_profile = "${aws_iam_instance_profile.ec2_ssm_profile.name}" // Handle System Manager Patch Manager

  tags = "${local.tags}"
}

/* Upgrade automatically the EC2 instance */
resource "null_resource" "bootstrap_database_host" {
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = "${file(pathexpand("~/.ssh/id_rsa"))}"
    host        = "${aws_instance.database_host.public_ip}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade",
    ]
  }
}

/*  ==> Handle System Manager Patch Manager */
/*
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2_ssm_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": {
      "Effect": "Allow",
      "Principal": {"Service": "ssm.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  }
EOF

  tags = "${local.tags}"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_role_policy_attachment" {
  role       = "${aws_iam_role.ec2_ssm_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_ssm_activation" "ec2_ssm_activation" {
  name               = "ec2_ssm_activation"
  iam_role           = "${aws_iam_role.ec2_ssm_role.id}"
  registration_limit = "5"
  depends_on         = ["aws_iam_role_policy_attachment.ec2_ssm_role_policy_attachment"]
  tags               = "${local.tags}"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2_ssm_profile"
  role = "${aws_iam_role.ec2_ssm_role.name}"
}

resource "aws_vpc_endpoint" "ec2_ssm_endpoint_ssm" {
  vpc_id            = "${aws_vpc.main_vpc.id}"
  service_name      = "com.amazonaws.${local.region}.ssm"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    "${aws_security_group.main_security_group.id}",
  ]

  subnet_ids = ["${aws_subnet.main_vpc_subnet_1.id}"]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2_ssm_endpoint_ec2messages" {
  vpc_id            = "${aws_vpc.main_vpc.id}"
  service_name      = "com.amazonaws.${local.region}.ec2messages"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    "${aws_security_group.main_security_group.id}",
  ]

  subnet_ids = ["${aws_subnet.main_vpc_subnet_1.id}"]

  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2_ssm_endpoint_ec2" {
  vpc_id            = "${aws_vpc.main_vpc.id}"
  service_name      = "com.amazonaws.${local.region}.ec2"
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    "${aws_security_group.main_security_group.id}",
  ]

  subnet_ids = ["${aws_subnet.main_vpc_subnet_1.id}"]

  private_dns_enabled = true
}
*/
/*  ==> Handle System Manager Patch Manager */

