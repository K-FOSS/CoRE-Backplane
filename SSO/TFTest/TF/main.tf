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

provider "authentik" {
  url   = "https://idp.mylogin.space"
  token = "${var.aaatoken}"
  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
}

output "hello_world" {
  value = "hey hey ya, ${var.aaatoken}!"
}
