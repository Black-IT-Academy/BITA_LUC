# ---------------------------------------------------------------------------
# The only variable without a default is instance_count, so `terraform apply`
# interactively prompts "How many Ubuntu lab instances should be created?".
# ---------------------------------------------------------------------------

variable "instance_count" {
  description = "How many Ubuntu lab instances (one per student)? Ignored by terraform destroy - answer 0 there."
  type        = number

  # Deliberately permits 0 so `terraform destroy` can be answered with 0.
  # Variable validation runs on EVERY operation, destroy included, so the real
  # "at least one box" rule lives in a precondition on aws_instance.vpn -
  # Terraform skips preconditions on destroy plans. See vpn.tf.
  validation {
    condition     = var.instance_count >= 0 && var.instance_count <= 25
    error_message = "Pick between 0 and 25. Use 0 only when destroying."
  }
}

variable "aws_region" {
  description = "AWS region to build the lab in."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile used for credentials. Set this in terraform.tfvars."
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "bita-capstone"
}

variable "instance_type" {
  description = "EC2 instance type for the student lab boxes."
  type        = string
  default     = "t3.micro"
}

variable "vpn_instance_type" {
  description = "EC2 instance type for the OpenVPN / NAT gateway host."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR for the lab VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet that only holds the OpenVPN/NAT host."
  type        = string
  default     = "10.50.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet that holds the student lab instances (no public IPs)."
  type        = string
  default     = "10.50.10.0/24"
}

variable "vpn_client_cidr" {
  description = "Address pool handed out to OpenVPN clients."
  type        = string
  default     = "10.8.0.0/24"
}

variable "vpn_port" {
  description = "UDP port OpenVPN listens on."
  type        = number
  default     = 1194
}

variable "vpn_allowed_source_cidrs" {
  description = "Who may reach the OpenVPN UDP port. Tighten this to your office/home ranges if you can."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_ssh_cidrs" {
  description = "Optional CIDRs allowed to SSH directly to the VPN host for break-glass admin. Empty = nobody."
  type        = list(string)
  default     = []
}

variable "admin_ssh_public_key" {
  description = "Optional SSH public key installed on ubuntu@ for break-glass admin access. Empty = password auth only."
  type        = string
  default     = ""
}

variable "ubuntu_ami_name_filter" {
  description = "AMI name filter used to find the Ubuntu image."
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

variable "admin_username" {
  description = "Full-sudo account created on every lab instance."
  type        = string
  default     = "bita-admin"
}

variable "lab_username" {
  description = "Deliberately broken account students must repair."
  type        = string
  default     = "bita-user"
}

variable "lab_marker" {
  description = "String the nginx lab site must serve for the health check to pass."
  type        = string
  default     = "BITA-LAB-8081-OK"
}

variable "noncritical_service" {
  description = "A non-critical systemd service the student must stop AND disable. Left running + enabled by the fault injector."
  type        = string
  default     = "atd"
}
