###############################################################################
# AWS Managed Instance Role
###############################################################################
resource "aws_iam_role" "default" {
  name = local.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "ssm.amazonaws.com"
          ]
        }
      },
    ]
  })

  tags = local.tags
}

data "aws_iam_policy" "ssm" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.default.name
  policy_arn = data.aws_iam_policy.ssm.arn
}

data "aws_iam_policy" "cw" {
  name = "CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cw" {
  role       = aws_iam_role.default.name
  policy_arn = data.aws_iam_policy.cw.arn
}

resource "aws_iam_policy" "default" {
  name        = local.name

  policy = file("./files/aws_policy.json")
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.name
  policy_arn = aws_iam_policy.default.arn
}

# #############################################################################
# Provision Certificates to Secure Access to Docker
# #############################################################################
resource "tls_private_key" "ca" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem
  subject {
    country       = local.organization.country
    province      = local.organization.province
    locality      = local.organization.locality
    organization  = local.organization.name
    common_name   = "${local.name}.${local.domain}"
  }
  validity_period_hours = 43800
  allowed_uses          = [
    "key_encipherment",
    "digital_signature",
    "cert_signing"
  ]
  is_ca_certificate     = true
}

resource "tls_private_key" "server" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  subject {
    common_name   = "${local.name}.${local.domain}"
  }
  dns_names       = ["${local.name}.${local.domain}", local.name]
  ip_addresses    = [local.ip_address]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 43800

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

resource "tls_private_key" "client" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  subject {
    common_name  = "client"
  }
}

resource "tls_locally_signed_cert" "client_crt" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 43800

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth"
  ]
}

# #############################################################################
# Prepare User Data for Cloud Init
# #############################################################################
data "external" "get_session_token" {
  program = ["bash", "./files/get_session_token.sh"]
}

data "template_file" "user_data" {
  template = file("./files/user_data.tpl")
  vars = {
    aws_access_key_id     = data.external.get_session_token.result.access_key
    aws_secret_access_key = data.external.get_session_token.result.secret_key
    aws_session_token     = data.external.get_session_token.result.session_token
    description           = local.description
    domain                = local.domain
    hostname              = local.name
    log_group_name        = "/${var.GIT_REPOSITORY}/${local.name}"
    region                = data.aws_region.default.name
    role                  = aws_iam_role.default.name
    salt_environment      = local.salt_environment
    saltmaster            = var.SALTMASTER
    tags                  = join(" ", [ for key, value in local.tags : "\"Key=${key},Value=${value}\"" ])
    tlscacert             = indent(6, tls_self_signed_cert.ca.cert_pem)
    tlscert               = indent(6, tls_locally_signed_cert.server.cert_pem)
    tlskey                = indent(6, tls_private_key.server.private_key_pem)
  }
}

# #############################################################################
# Send User Data for Cloud Init to Proxmox Host
# #############################################################################
resource "null_resource" "user_data" {
  connection {
    type     = "ssh"
    user     = var.PVE_USER
    password = var.PVE_PASSWORD
    host     = var.PVE_HOST
  }

  triggers = {
    file = sha256(file("./files/user_data.tpl"))
  }

  provisioner "file" {
    content  = data.template_file.user_data.rendered
    destination = "/var/lib/vz/snippets/${sha256(data.template_file.user_data.rendered)}.cfg"
  }
}

# #############################################################################
# Provision Kubernetes Virtual Machine
# #############################################################################
resource "proxmox_vm_qemu" "default" {
  cicustom                = "user=local:snippets/${sha256(data.template_file.user_data.rendered)}.cfg"
  cloudinit_cdrom_storage = "local"
  clone                   = local.golden_image
  cores                   = 4
  desc                    = local.description
  full_clone              = true
  ipconfig0               = "ip=dhcp"
  memory                  = 4096
  name                    = local.name
  os_type                 = "cloud-init"
  pool                    = var.PVE_POOL
  sockets                 = 2
  target_node             = var.PVE_NODE

  disk {
    size      = "25G"
    storage   = "local"
    type      = "virtio"
  }

  network {
    model     = "e1000"
    bridge    = "vmbr0"
   }

  depends_on  = [
    null_resource.user_data,
  ]
}
