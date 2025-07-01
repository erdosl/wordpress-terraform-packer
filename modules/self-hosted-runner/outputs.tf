output "instance_id" {
  value = aws_instance.runner.id
}

output "private_ip" {
  value = aws_instance.runner.private_ip
}
