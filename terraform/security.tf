# Security groups decide WHO may talk to WHOM. They are stateful: if a request
# is allowed in, the reply is allowed back out automatically.
#
# The groups are chained by reference instead of by IP address:
#   internet -> web -> app -> database
# The app group says "accept traffic from the web group", not "from 10.0.0.5".
# That keeps working when servers are replaced and their IPs change.

# Web tier: the only group the internet can reach
resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-"
  description = "Web tier: HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# App tier: accepts traffic only from the web tier
resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-app-"
  description = "App tier: app port from the web tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the web tier"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# Data tier: accepts traffic only from the app tier, and has NO outbound rules.
# Defining no egress block removes the default "allow everything out" rule,
# so the database cannot start a connection to anything.
resource "aws_security_group" "data" {
  name_prefix = "${var.project_name}-data-"
  description = "Data tier: database port from the app tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Database port from the app tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-data-sg" }
}