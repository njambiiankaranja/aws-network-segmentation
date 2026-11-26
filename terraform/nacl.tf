# A network ACL is a second filter, applied at the edge of a whole subnet.
# Unlike a security group it is STATELESS: it checks every packet in each
# direction separately, so replies must be allowed explicitly too.
# Anything not allowed below is denied by the built-in final rule.
#
# Security group = who may talk to this server (stateful, per server)
# Network ACL    = what may cross this subnet's border (stateless, per subnet)
# Having both means one mistake does not open the vault.

resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.data[*].id

  # In: the database port, from the app subnets only
  dynamic "ingress" {
    for_each = var.app_subnet_cidrs

    content {
      rule_no    = 100 + ingress.key
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = var.db_port
      to_port    = var.db_port
    }
  }

  # Out: replies to the app subnets, on the temporary (ephemeral) ports
  # clients use for the return path
  dynamic "egress" {
    for_each = var.app_subnet_cidrs

    content {
      rule_no    = 100 + egress.key
      protocol   = "tcp"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  tags = { Name = "${var.project_name}-data-nacl" }
}