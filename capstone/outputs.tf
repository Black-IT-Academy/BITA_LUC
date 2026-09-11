locals {
  lab_instances = [
    for idx, inst in aws_instance.lab : {
      name         = inst.tags["Name"]
      instance_id  = inst.id
      private_ip   = inst.private_ip
      username     = var.admin_username
      password     = random_string.admin_password[idx].result
      lab_username = var.lab_username
      lab_password = random_string.lab_password[idx].result
      ssh_command  = "ssh ${var.admin_username}@${inst.private_ip}"
      ping_command = "ping ${inst.private_ip}"
      health_check = "http://${inst.private_ip}:8080"
      lab_site     = "http://${inst.private_ip}:8081"
    }
  ]

  instance_blocks = join("\n", [
    for i in local.lab_instances : <<-BLOCK
      ${i.name}
        internal IP        : ${i.private_ip}
        ping to validate   : ${i.ping_command}
        SSH (sudo account) : ${i.ssh_command}
            username       : ${i.username}
            password       : ${i.password}
        broken account you must repair (do NOT change its password):
            username       : ${i.lab_username}
            password       : ${i.lab_password}
        health check page  : ${i.health_check}
        lab web site       : ${i.lab_site}
    BLOCK
  ])

  connection_details = templatefile("${path.module}/templates/connection-details.txt.tftpl", {
    ovpn_path           = abspath(local_sensitive_file.ovpn.filename)
    ovpn_filename       = basename(local_sensitive_file.ovpn.filename)
    vpn_endpoint        = aws_eip.vpn.public_ip
    vpn_port            = var.vpn_port
    vpn_client_cidr     = var.vpn_client_cidr
    private_subnet_cidr = var.private_subnet_cidr
    admin_user          = var.admin_username
    first_instance_ip   = length(local.lab_instances) > 0 ? local.lab_instances[0].private_ip : "<no instances>"
    instance_blocks     = local.instance_blocks
  })
}

output "lab_instances" {
  description = "Per-instance internal IP and initial credentials - this is what you hand to students."
  value       = local.lab_instances
}

output "vpn_endpoint" {
  description = "Public address of the OpenVPN concentrator."
  value       = "${aws_eip.vpn.public_ip}:${var.vpn_port}/udp"
}

output "vpn_profile" {
  description = "Path to the generated OpenVPN client profile."
  value       = abspath(local_sensitive_file.ovpn.filename)
}

output "connection_instructions" {
  description = "Copy/paste connection guide: VPN setup for Windows/macOS/Linux, ping validation, and per-box credentials."
  value       = local.connection_details
}

resource "local_sensitive_file" "connection_details" {
  filename        = "${path.module}/generated/CONNECTION-DETAILS.txt"
  file_permission = "0600"
  content         = local.connection_details
}
