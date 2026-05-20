output "public_ip" {
  description = "Public IP of the bastion host — use this to SSH in"
  value       = aws_instance.bastion.public_ip
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}
