resource "aws_security_group" "vpn" {
  name        = "${var.project_name}-vpn-sg"
  description = "OpenVPN concentrator / NAT host"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "OpenVPN"
    from_port   = var.vpn_port
    to_port     = var.vpn_port
    protocol    = "udp"
    cidr_blocks = var.vpn_allowed_source_cidrs
  }

  # Return path for NAT'd traffic coming back from the private subnet.
  ingress {
    description = "All traffic from the private lab subnet (NAT return path)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  dynamic "ingress" {
    for_each = length(var.admin_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "Break-glass admin SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.admin_ssh_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vpn-sg" }
}

resource "aws_security_group" "lab" {
  name        = "${var.project_name}-lab-sg"
  description = "Student lab instances - reachable only through the VPN"
  vpc_id      = aws_vpc.lab.id

  # Traffic arriving via the VPN host, whether NAT'd to its private IP...
  ingress {
    description     = "Anything arriving from the VPN host"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.vpn.id]
  }

  # ...or routed straight through with the VPN client IP preserved.
  ingress {
    description = "Anything from the OpenVPN client pool"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-lab-sg" }
}
