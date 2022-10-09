terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "2022.8.1"
    }

    local = {
      source = "hashicorp/local"
      version = "2.2.3"
    }
  }
}

provider "authentik" {
  url   = "https://idp.mylogin.space"

  # Optionally set insecure to ignore TLS Certificates
  # insecure = true
}

provider "local" {

}

data "local_file" "tlscert" {
  filename = "${path.module}/TLS/MyLogin/TLS.crt"
}

data "local_file" "tlskey" {
  filename = "${path.module}/TLS/MyLogin/TLS.key"
}


resource "authentik_certificate_key_pair" "myloginspace" {
  name = "MyLogin.Space Wildcard"

  certificate_data = "${data.local_file.tlscert.content}"
  key_data = "${data.local_file.tlskey.content}"
}

