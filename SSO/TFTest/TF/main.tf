terraform {
  required_version = ">= 0.12.26"
}

variable "aaatoken" {
   type = string
   default = "tfctl-rc"
   description = "Authentik Token"
}

output "hello_world" {
  value = "hey hey ya, ${var.aaatoken}!"
}
