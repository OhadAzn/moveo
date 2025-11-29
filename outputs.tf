output "alb_url" {
  value = "http://${module.alb.alb_dns}"
}

output "ec2_private_ip" {
  value = module.compute.instance_ip
}
