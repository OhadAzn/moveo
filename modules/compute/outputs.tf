output "instance_id" {
  value = aws_instance.web.id
}

output "instance_ip" {
  value = aws_instance.web.private_ip
}
