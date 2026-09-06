# ---------------------------------------------------------------------------
# OpenVPN PKI, generated entirely by Terraform (no easy-rsa needed).
# ---------------------------------------------------------------------------

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  validity_period_hours = 8760
  is_ca_certificate     = true

  subject {
    common_name  = "${var.project_name}-ca"
    organization = "BITA Capstone Lab"
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "vpn_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_server" {
  private_key_pem = tls_private_key.vpn_server.private_key_pem

  subject {
    common_name  = "${var.project_name}-vpn-server"
    organization = "BITA Capstone Lab"
  }
}

resource "tls_locally_signed_cert" "vpn_server" {
  cert_request_pem      = tls_cert_request.vpn_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760

  # server_auth is what the client's `remote-cert-tls server` check requires.
  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "tls_private_key" "vpn_client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_client" {
  private_key_pem = tls_private_key.vpn_client.private_key_pem

  subject {
    common_name  = "${var.project_name}-student"
    organization = "BITA Capstone Lab"
  }
}

resource "tls_locally_signed_cert" "vpn_client" {
  cert_request_pem      = tls_cert_request.vpn_client.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760

  allowed_uses = ["digital_signature", "key_encipherment", "client_auth"]
}

# ---------------------------------------------------------------------------
# Optional break-glass key pair
# ---------------------------------------------------------------------------

resource "aws_key_pair" "admin" {
  count = var.admin_ssh_public_key == "" ? 0 : 1

  key_name   = "${var.project_name}-admin"
  public_key = var.admin_ssh_public_key
}

# ---------------------------------------------------------------------------
# VPN / NAT host
# ---------------------------------------------------------------------------

resource "aws_instance" "vpn" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.vpn_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.vpn.id]
  key_name               = var.admin_ssh_public_key == "" ? null : aws_key_pair.admin[0].key_name

  # Required for this box to route traffic on behalf of the private subnet.
  source_dest_check = false

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/vpn-cloud-init.yaml.tftpl", {
    vpn_port            = var.vpn_port
    vpn_client_cidr_ip  = cidrhost(var.vpn_client_cidr, 0)
    vpn_client_netmask  = cidrnetmask(var.vpn_client_cidr)
    vpn_client_cidr     = var.vpn_client_cidr
    private_subnet_ip   = cidrhost(var.private_subnet_cidr, 0)
    private_subnet_mask = cidrnetmask(var.private_subnet_cidr)
    private_subnet_cidr = var.private_subnet_cidr
    ca_cert             = trimspace(tls_self_signed_cert.ca.cert_pem)
    server_cert         = trimspace(tls_locally_signed_cert.vpn_server.cert_pem)
    server_key          = trimspace(tls_private_key.vpn_server.private_key_pem)
  }))

  # Replace the box if the VPN config materially changes.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.project_name}-vpn" }

  # The "at least one lab box" rule. It lives here rather than on the variable
  # because variable validation also fires on `terraform destroy` (where 0 is
  # the natural answer), whereas preconditions are skipped on destroy plans.
  # It hangs off the VPN host because that resource always exists - a
  # precondition on aws_instance.lab would never run when count is 0.
  lifecycle {
    # data.aws_ami.ubuntu (most_recent = true) re-resolves on every apply.
    # Pinning the VPN host to its original image keeps a newer Ubuntu release
    # from replacing it when you add lab boxes later. The Elastic IP survives a
    # replacement (aws_eip re-associates in place, same address) and the PKI
    # lives in state, so already-distributed .ovpn files stay valid - but the
    # rebuild still drops every connected student for the boot window.
    ignore_changes = [ami]

    precondition {
      condition     = var.instance_count >= 1 && var.instance_count <= 25
      error_message = "instance_count must be between 1 and 25 to build the lab (0 is only for destroy)."
    }
  }
}

resource "aws_eip" "vpn" {
  instance = aws_instance.vpn.id
  domain   = "vpc"

  tags = { Name = "${var.project_name}-vpn-eip" }
}

# ---------------------------------------------------------------------------
# Client profile written to ./generated/
# ---------------------------------------------------------------------------

resource "local_sensitive_file" "ovpn" {
  filename        = "${path.module}/generated/${var.project_name}.ovpn"
  file_permission = "0600"

  content = templatefile("${path.module}/templates/client.ovpn.tftpl", {
    remote_host = aws_eip.vpn.public_ip
    vpn_port    = var.vpn_port
    ca_cert     = trimspace(tls_self_signed_cert.ca.cert_pem)
    client_cert = trimspace(tls_locally_signed_cert.vpn_client.cert_pem)
    client_key  = trimspace(tls_private_key.vpn_client.private_key_pem)
  })
}
