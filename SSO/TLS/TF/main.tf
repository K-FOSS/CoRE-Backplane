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

    null = {
      source = "hashicorp/null"
      version = "3.1.1"
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

provider "null" {
  # Configuration options
}

provider "time" {
  # Configuration options
}

provider "local" {
  # Configuration options
}

resource "null_resource" "previous" {}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [null_resource.previous]

  create_duration = "60s"
}



// resource "authentik_certificate_key_pair" "myloginspace" {
//   name = "MyLogin.Space Wildcard"

//   certificate_data = "${data.local_file.tlscert}"
//   key_data = "${data.local_file.tlssecret}"
// }

