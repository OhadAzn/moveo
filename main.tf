module "network" {
  source = "./modules/network"

  vpc_cidr = var.vpc_cidr
  name     = local.name
  azs      = var.azs
  tags     = local.tags
}

module "alb" {
  source = "./modules/alb"

  name           = local.name
  vpc_id         = module.network.vpc_id
  public_subnets = module.network.public_subnet_ids
  instance_id    = ""
  tags           = local.tags
}

module "compute" {
  source = "./modules/compute"

  name                 = local.name
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.private_subnet_ids[0]
  alb_sg_id            = module.alb.alb_sg_id
  depends_on           = [module.network]
  tags                 = local.tags



}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.alb.target_group_arn
  target_id        = module.compute.instance_id
  port             = 80
}
