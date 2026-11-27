# One small test server per tier. Each runs a tiny listener on its tier's port,
# so we can try to connect to it from other tiers and see what the network allows.
# The data-tier server stands in for a database: it listens on the database port,
# which is all the network cares about.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Public tier: reachable from the internet on port 80
resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/tier_server.sh.tftpl", {
    tier = "web"
    port = 80
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project_name}-web" }
}

# App tier: no public IP, reachable only from the web tier
resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.app[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = templatefile("${path.module}/tier_server.sh.tftpl", {
    tier = "app"
    port = var.app_port
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project_name}-app" }

  # The Session Manager endpoints must exist so the agent can register
  depends_on = [aws_vpc_endpoint.ssm]
}

# Data tier: no public IP, no outbound access, and deliberately NO shell access.
# Nobody logs in to the vault. It only answers on the database port.
resource "aws_instance" "data" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.data[0].id
  vpc_security_group_ids = [aws_security_group.data.id]

  user_data = templatefile("${path.module}/tier_server.sh.tftpl", {
    tier = "data"
    port = var.db_port
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project_name}-data" }
}