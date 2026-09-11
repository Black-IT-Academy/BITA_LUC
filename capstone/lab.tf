# ---------------------------------------------------------------------------
# Per-student credentials. random_string (not random_password) is used on
# purpose: these are throwaway lab creds that MUST be printable in the
# terraform output so they can be handed out.
# ---------------------------------------------------------------------------

resource "random_string" "admin_password" {
  count = var.instance_count

  length           = 16
  special          = true
  override_special = "@#%^*-_=+" # shell/chpasswd-safe: no quotes, $, \ or :
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "random_string" "lab_password" {
  count = var.instance_count

  length           = 16
  special          = true
  override_special = "@#%^*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "aws_instance" "lab" {
  count = var.instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.lab.id]
  key_name               = var.admin_ssh_public_key == "" ? null : aws_key_pair.admin[0].key_name

  # gzip'd because EC2 caps raw user_data at 16 KB and these payload files
  # (health_check.py in particular) do not fit uncompressed. cloud-init
  # detects and inflates gzip automatically.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/lab-cloud-init.yaml.tftpl", {
    hostname        = format("%s-%02d", var.project_name, count.index + 1)
    admin_user      = var.admin_username
    admin_pass      = random_string.admin_password[count.index].result
    lab_user        = var.lab_username
    lab_pass        = random_string.lab_password[count.index].result
    lab_marker      = var.lab_marker
    noncrit_service = var.noncritical_service
    setup_sh        = file("${path.module}/files/setup.sh")
    break_sh        = file("${path.module}/files/break-lab.sh")
    health_py       = file("${path.module}/files/health_check.py")
    motd            = templatefile("${path.module}/files/lab-reference.txt", { noncrit_service = var.noncritical_service })
  }))

  user_data_replace_on_change = true

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  # The lab boxes have no public IP - their only route to the Ubuntu archive
  # is through the VPN host, so it has to exist and be routable first.
  depends_on = [
    aws_instance.vpn,
    aws_route_table_association.private,
  ]

  # data.aws_ami.ubuntu uses most_recent = true, so it re-resolves on every
  # apply. Without this, a newer Ubuntu image published between applies would
  # change the ami and REPLACE every existing box. Pin already-built boxes to
  # the image they booted with; new boxes (added by raising instance_count)
  # are still created from the current AMI. Taint a box if you truly want it
  # rebuilt on a newer image.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = format("%s-%02d", var.project_name, count.index + 1)
    Role = "student-lab"
  }
}
