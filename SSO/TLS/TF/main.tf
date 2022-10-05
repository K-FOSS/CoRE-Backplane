terraform {
  required_version = ">= 0.12.26"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "2022.8.1"
    }
  }
}

variable "aaatoken" {
  type = string
  default = "tfctl-rc"
  description = "Authentik Token"
}

variable "tlscert" {
  type = string
  default = "tfctl-rc"
  description = "Authentik Token"
}

variable "tlssecret" {
  type = string
  default = "tfctl-rc"
  description = "Authentik Token"
}


provider "authentik" {
  url   = "https://idp.mylogin.space"
  token = "${var.aaatoken}"
  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
}


resource "authentik_certificate_key_pair" "myloginspace" {
  name = "MyLogin.Space Wildcard"

  certificate_data = "${var.tlscert}"
  key_data = "${var.tlssecret}"
}

output "hello_world" {
  value = "hey hey ya, ${var.aaatoken}! my cert is: ${var.tlscert} and my secret is: ${var.tlssecret}"
}
