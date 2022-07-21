locals {
  name_string = "${var.prefix}${var.suffix}"
}

resource "random_string" "namestring" {
  length  = var.random_length
  special = false
  upper   = false
  lower   = true
}