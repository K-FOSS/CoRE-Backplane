terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "2022.8.1"
    }
  }
}

variable "Token" {
  type = string
  default = "tfctl-rc"
  description = "Authentik Token"
}

variable "Cert" {
  type = string
  default = "tfctl-rc"
  description = "TLS Cert Public"
}

provider "authentik" {
  url   = "https://idp.mylogin.space"
  token = "${var.Token}"
  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
}


// resource "authentik_certificate_key_pair" "myloginspace" {
//   name = "MyLogin.Space Wildcard"

//   certificate_data = "${var.tls.crt}"
//   key_data = "${var.tlssecret}"
// }

output "hello_world" {
  value = "hey hey ${var.Token}  blah ya, test"
}

output "cert" {
  value = var.Cert
}
