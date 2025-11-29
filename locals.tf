locals {
  name = "${var.project}-${var.environment}"

  tags = {
    env   = var.environment
    owner = var.owner
  }
}
