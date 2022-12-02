module "security_group" {
  source              = "terraform-aws-modules/security-group/aws//modules/web"
  version             = ">=3.17.0"
  name                = "${var.name_prefix}-sg"
  vpc_id              = var.vpc_id
  ingress_cidr_blocks = var.ingress_cidr_blocks
  tags                = var.tags
}
