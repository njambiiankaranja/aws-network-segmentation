variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy into"
}

variable "project_name" {
  type        = string
  default     = "netseg"
  description = "Prefix for resource names and the Project tag"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the whole VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
  description = "Public tier: load balancers and anything that must face the internet. One per availability zone"
}

variable "app_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
  description = "Private app tier: application servers. One per availability zone"
}

variable "data_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
  description = "Isolated data tier: databases. One per availability zone"
}

variable "enable_nat" {
  type        = bool
  default     = false
  description = "Create a NAT Gateway so the app tier can reach the internet. It costs money every hour, so it is off by default"
}
variable "app_port" {
  type        = number
  default     = 8080
  description = "Port the application tier listens on"
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "Port the database tier listens on (5432 is PostgreSQL)"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type for the three test servers"
}
