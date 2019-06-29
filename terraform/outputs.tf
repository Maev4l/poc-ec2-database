output "ec2_public_dns" {
    value ="${aws_instance.database_host.public_dns}"
}
