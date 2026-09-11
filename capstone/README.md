# Terraform capstone build for LUC

Answer one question — *how many students?* — and this builds N Ubuntu boxes,
each pre-loaded with a set of injected faults, reachable **only** through an
OpenVPN tunnel that Terraform builds and hands you as a single `.ovpn` file.
Every box self-grades in real time on a web page students can screenshot to
prove their work landed.

```
                     internet
                        │  UDP 1194 (OpenVPN)
                ┌───────▼────────┐
                │ VPN / NAT host │  public subnet  10.50.1.0/24
                │  Elastic IP    │  source/dest check off
                └───────┬────────┘
                        │  routes 0.0.0.0/0 for the private subnet
        ┌───────────────┼───────────────┐
   ┌────▼────┐     ┌────▼────┐     ┌────▼────┐   private subnet 10.50.10.0/24
   │ lab-01  │     │ lab-02  │ ... │ lab-NN  │   NO public IPs
   │ :22 :8080 :8081                          │
   └─────────┘     └─────────┘     └─────────┘
```

The lab boxes have no public IP and no inbound path from the internet. Their
only route out is NAT'd through the VPN host, and their security group accepts
traffic from just two places: the VPN host's own security group, and the
`10.8.0.0/24` OpenVPN client pool.

## Prerequisites

* **Terraform** ≥ 1.5
* **An AWS account** and a named CLI profile with EC2/VPC permissions
* **An OpenVPN client** on your own machine, to test the tunnel before a cohort
  touches it

```bash
# swap in your own profile name; `aws configure list-profiles` lists them
aws sts get-caller-identity --profile your-aws-profile
```

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars    # then edit it
terraform init
terraform apply                                 # prompts for instance_count
```

Terraform asks:

```
var.instance_count
  How many Ubuntu lab instances (one per student)?
  Enter a value:
```

On completion you get, both on stdout and written to `generated/`:

* `generated/bita-capstone.ovpn` — the VPN profile to hand out (mode 0600)
* `generated/CONNECTION-DETAILS.txt` — per-student block: internal IP, username,
  initial password, ping command, health-check URL, plus OpenVPN instructions
  for Windows / macOS / Linux

Reprint them at any time, without applying:

```bash
terraform output -raw connection_instructions
terraform output -json lab_instances | jq
```

First boot takes roughly 3–5 minutes per box: it installs packages through the
NAT host, builds the box out, verifies it, and only then runs the injector.
Until that finishes the health page will not answer.

## Handing the lab to students

Give each student **two** things: the `.ovpn` file, and their own block out of
`CONNECTION-DETAILS.txt`. Everything else is discoverable from the box itself —
`/etc/motd` briefs them the moment they log in.

## Adding and removing boxes mid-cohort

Boxes are named `bita-capstone-01` … `-NN` from their `count` index, so the
numbering follows `instance_count` directly.

### Add boxes to a running lab

```bash
terraform apply          # answer instance_count = <current + how many you want>
```

That is the whole procedure — no VPN step, no new profile to hand out. Going
from 1 box to 3 plans as:

```
aws_instance.lab[1]                       create
aws_instance.lab[2]                       create
random_string.admin_password[1..2]        create
random_string.lab_password[1..2]          create
local_sensitive_file.connection_details   delete,create

untouched: aws_instance.lab[0], aws_instance.vpn, aws_eip.vpn,
           local_sensitive_file.ovpn, and the whole PKI
```

**Running boxes are not touched.** Their instances, private IPs and credentials
are left alone, and the VPN host is not restarted — students who are connected
stay connected through the whole apply.

**New boxes are reachable the moment they finish booting**, with no client
reconnect and no reissued `.ovpn`, because nothing in the design is per-box:

* the server pushes a route for the **entire private subnet**
  (`push "route 10.50.10.0 255.255.255.0"`), not one route per instance, so any
  new address in that subnet is already routed for every connected client
* the lab security group admits the **whole OpenVPN client pool**
  (`cidr_blocks = [var.vpn_client_cidr]`) plus the VPN host's security group

**Credentials land in the file automatically.** `local.lab_instances` in
`outputs.tf` is a comprehension over *all* of `aws_instance.lab`, so every box
gets a block in `generated/CONNECTION-DETAILS.txt`.

Give a new box 3–5 minutes before it answers — it has no public IP and installs
through the VPN host, so it is subject to the same mirror behaviour as a first
build. Confirm it is live from your VPN-connected machine:

```bash
ping 10.50.10.x                    # the new box's internal IP
curl http://10.50.10.x:8080        # its self-grading health page
```

One caveat: existing boxes keep the AMI they booted with (`ignore_changes =
[ami]`), while a box added later is built from whatever `most_recent` Ubuntu
image is current. A long-running lab can end up spanning releases. That is
deliberate — the alternative is replacing every running box the day Canonical
publishes a new image.

### Remove one box, not the whole lab

Which command depends on *which* box, because the instances use `count`.

**If it is the highest-numbered box** — the normal case when a student leaves —
just lower the number:

```bash
terraform apply          # answer instance_count = <current - 1>
```

`count` removes from the end, so this destroys `bita-capstone-NN` and its
credentials. Every lower-numbered box keeps its index, its instance and its
password. The floor is **1**; a precondition rejects 0 on apply:

```
Error: Resource precondition failed
instance_count must be between 1 and 25 to build the lab (0 is only for destroy).
```

**If it is any other box**, target it directly (0-based — `lab[1]` is
`bita-capstone-02`):

```bash
terraform destroy -target='aws_instance.lab[1]'
```

```
# aws_instance.lab[1] will be destroyed
# local_sensitive_file.connection_details will be destroyed
Plan: 0 to add, 0 to change, 2 to destroy
```

The VPN host, the Elastic IP, the PKI and the other lab boxes are untouched —
the tunnel stays up and everyone else keeps working. Two things to know:

1. **It also deletes `generated/CONNECTION-DETAILS.txt`**, because that file
   depends on the instances. Regenerate it with
   `terraform output -raw connection_instructions > generated/CONNECTION-DETAILS.txt`,
   or let the next apply rewrite it.
2. **It is a suspension, not a deletion.** State still expects `instance_count`
   boxes, so the next plain `terraform apply` rebuilds it. Use this to stop
   paying for a box mid-cohort, not to permanently resize the lab.

There is no clean way to *permanently* remove a middle box with `count`: each
box's user_data is derived from its index (hostname `bita-capstone-%02d` and
per-index passwords), so shifting indices with `terraform state mv` makes the
user_data no longer match and `user_data_replace_on_change = true` rebuilds the
box anyway. If a future cohort needs students added and removed freely, the
instances want to be keyed by student with `for_each` instead of `count`.

## Teardown and cost

```bash
terraform destroy
```

Nothing is created outside the VPC, so destroy is complete. Running cost is two
`t3.micro` instances plus ~20 GB of gp3 for a two-box lab — on the order of
**$0.03/hour**, scaling by roughly **$0.012/hour** per extra student box.
**Destroy the lab when the cohort finishes.**

## Layout

```
versions.tf              providers and pinned provider versions
variables.tf             all knobs; instance_count is the only one without a default
network.tf               VPC, subnets, IGW, route tables, Ubuntu AMI lookup
security_groups.tf       VPN host SG and lab SG (VPN-only ingress)
vpn.tf                   Terraform-generated PKI, VPN/NAT host, .ovpn generation
lab.tf                   per-student credentials and lab instances
outputs.tf               connection details (stdout + generated/)
terraform.tfvars.example copy to terraform.tfvars and edit

templates/               rendered by Terraform at plan time
  lab-cloud-init.yaml.tftpl      first-boot config for a student box
  vpn-cloud-init.yaml.tftpl      first-boot config for the VPN/NAT host
  client.ovpn.tftpl              the VPN profile handed to students
  connection-details.txt.tftpl   the credential sheet

files/                   payload dropped on each lab box
  setup.sh                 first-boot provisioner
  break-lab.sh             the fault injector (also the "reset lab" button)
  health_check.py          the self-grading web service on :8080
  lab-reference.txt        /etc/motd shown to students at login

generated/               .ovpn and credential sheet land here (gitignored)
```

## Operating notes

* **Treat `terraform.tfstate` as a secret.** The generated VPN PKI and every
  student password live in it. Point it at an encrypted remote backend before
  using this for anything beyond a throwaway cohort.

* **Never commit `terraform.tfvars`.** It pins your source IP and your public
  key. It is gitignored; keep it that way. `terraform.tfvars.example` carries
  placeholder values for everything.

* **Tighten `vpn_allowed_source_cidrs`.** It defaults to `0.0.0.0/0` so students
  on unknown networks can connect. If you know the source ranges, set them.

* **Set up break-glass access before a cohort, not during one.** The lab boxes
  have no public IP, so a VPN host that fails to boot leaves destroy/rebuild as
  the only option. `admin_ssh_cidrs` + `admin_ssh_public_key` in
  `terraform.tfvars` give you a way in that does not depend on the tunnel.

* **The health page reports symptoms only.** Anything that would shortcut the
  exercise is withheld from `:8080`, `/json` and `bita-check`. Instructors get
  the full view with `bita-check --evidence`, which is never served over HTTP.
  Note that `bita-admin` has passwordless sudo, so a determined student can
  still read the payload under `/opt/bita`. Treat concealment as a speed bump,
  not a wall.

* **Reset a box** without rebuilding it: `sudo /opt/bita/break-lab.sh`.

* **Provisioning log** on each box: `/var/log/bita-setup.log`, plus the usual
  `/var/log/cloud-init-output.log`.

* **Changing anything in `files/` or `templates/`** changes user_data, and
  `user_data_replace_on_change = true` means the next apply *replaces* the
  instances. That is intentional — a half-patched lab box is worse than a new one.

* **One profile, many students.** The PKI mints a single client certificate
  (`CN=<project>-student`) and every student connects with it, so the server
  runs `duplicate-cn`. Two consequences: `status.log` shows the same common name
  for everyone (tell sessions apart by Client ID and real address, not by name),
  and revoking one student means revoking the cohort. If a future cohort needs
  per-student attribution or revocation, that is the point to switch to a
  per-student keypair in `vpn.tf` and one `.ovpn` each.

* **user_data budget.** EC2 caps raw user_data at 16 KB. The lab cloud-config is
  gzipped (`base64gzip`) and currently lands around 11.7 KB. If you add payload
  to `files/`, re-check the size before you trust an apply:

  ```bash
  terraform console -var instance_count=1 <<'EOF'
  length(base64gzip(templatefile("./templates/lab-cloud-init.yaml.tftpl", {
    hostname = "x", admin_user = "a", admin_pass = "b",
    lab_user = "c", lab_pass = "d", lab_marker = "m",
    noncrit_service = "s",
    setup_sh  = file("./files/setup.sh"),
    break_sh  = file("./files/break-lab.sh"),
    health_py = file("./files/health_check.py"),
    motd      = templatefile("./files/lab-reference.txt", { noncrit_service = "s" }),
  })))
  EOF
  ```
