output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public tier subnet IDs"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Private app tier subnet IDs"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Isolated data tier subnet IDs"
  value       = aws_subnet.data[*].id
}

output "nat_enabled" {
  description = "Whether a NAT Gateway exists (it costs money while it does)"
  value       = var.enable_nat
}

output "web_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "web_private_ip" {
  description = "Private IP of the web server"
  value       = aws_instance.web.private_ip
}

output "app_private_ip" {
  description = "Private IP of the app server (it has no public IP)"
  value       = aws_instance.app.private_ip
}

output "data_private_ip" {
  description = "Private IP of the data server (it has no public IP)"
  value       = aws_instance.data.private_ip
}

output "web_session_command" {
  description = "Open a shell on the web server"
  value       = "aws ssm start-session --target ${aws_instance.web.id}"
}

output "app_session_command" {
  description = "Open a shell on the app server"
  value       = "aws ssm start-session --target ${aws_instance.app.id}"
}

output "flow_log_group" {
  description = "CloudWatch log group that holds the flow logs"
  value       = aws_cloudwatch_log_group.flow.name
}