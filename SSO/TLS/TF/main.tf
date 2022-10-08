terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "2022.8.1"
    }

    time = {
      source = "hashicorp/time"
      version = "0.8.0"
    }
  }
}

variable "keycloak_administrator_password" {
  type = string
  description = "Authentik Token"
}

provider "authentik" {
  url   = "https://idp.mylogin.space"
  token = var.keycloak_administrator_password
  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
}

provider "time" {
  # Configuration options
}

resource "null_resource" "previous" {}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [null_resource.previous]

  create_duration = "30s"
}



// resource "authentik_certificate_key_pair" "myloginspace" {
//   name = "MyLogin.Space Wildcard"

//   certificate_data = "${var.tls.crt}"
//   key_data = "${var.tlssecret}"
// }

