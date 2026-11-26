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