locals {
  len_public_subnets  = length(var.public_subnets)
  len_private_subnets = length(var.private_subnets)

  max_subnet_length = max(
    local.len_private_subnets,
    local.len_public_subnets,
  )

  vpc_id = aws_vpc.this.id

  azs = length(var.azs) > 0 ? var.azs : data.aws_availability_zones.available.names
}

data "aws_availability_zones" "available" {
  state = "available"
}


################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block = var.cidr

  assign_generated_ipv6_cidr_block = false

  instance_tenancy     = "default"
  enable_dns_hostnames = "true"
  enable_dns_support   = "true"

  tags = merge(
    { "Name" = var.name },
    var.tags,
  )
}

################################################################################
# Publiс Subnets
################################################################################

resource "aws_subnet" "public" {
  count = local.len_public_subnets

  availability_zone    = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  cidr_block           = element(concat(var.public_subnets, [""]), count.index)
  vpc_id               = local.vpc_id

  tags = merge(
    {
      Name = try(
        format("${var.name}-public-%s", element(local.azs, count.index))
      )
    },
    var.tags,
  )
}

locals {
  num_public_route_tables = local.len_public_subnets
}

resource "aws_route_table" "public" {

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = "${var.name}-public",
    },
    var.tags,
  )
}

resource "aws_route_table_association" "public" {
  count = local.len_public_subnets

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id

  timeouts {
    create = "5m"
  }
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = local.len_private_subnets

  availability_zone    = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  cidr_block           = element(concat(var.private_subnets, [""]), count.index)
  vpc_id               = local.vpc_id

  tags = merge(
    {
      Name = try(
        format("${var.name}-private-%s", element(local.azs, count.index))
      )
    },
    var.tags,
  )
}

# There are as many routing tables as the number of NAT gateways
resource "aws_route_table" "private" {
  count = local.nat_gateway_count

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format(
        "${var.name}-private-%s",
        element(local.azs, count.index),
      )
    },
    var.tags,
  )
}

resource "aws_route_table_association" "private" {
  count = local.len_private_subnets

  subnet_id = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    count.index,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = var.name },
    var.tags,
  )
}

################################################################################
# NAT Gateway
################################################################################

locals {
  nat_gateway_count = local.max_subnet_length
  nat_gateway_ips   = aws_eip.nat[*].id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(local.azs, count.index),
      )
    },
    var.tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = element(
    local.nat_gateway_ips,
    count.index,
  )
  subnet_id = element(
    aws_subnet.public[*].id,
    count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(local.azs, count.index),
      )
    },
    var.tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = local.nat_gateway_count

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

################################################################################
# Default Network ACLs
################################################################################

resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  # subnet_ids is using lifecycle ignore_changes, so it is not necessary to list
  # any explicitly. See https://github.com/terraform-aws-modules/terraform-aws-vpc/issues/736
  subnet_ids = null

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      action          = ingress.value.action
      cidr_block      = lookup(ingress.value, "cidr_block", null)
      from_port       = ingress.value.from_port
      icmp_code       = lookup(ingress.value, "icmp_code", null)
      icmp_type       = lookup(ingress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(ingress.value, "ipv6_cidr_block", null)
      protocol        = ingress.value.protocol
      rule_no         = ingress.value.rule_no
      to_port         = ingress.value.to_port
    }
  }
  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      action          = egress.value.action
      cidr_block      = lookup(egress.value, "cidr_block", null)
      from_port       = egress.value.from_port
      icmp_code       = lookup(egress.value, "icmp_code", null)
      icmp_type       = lookup(egress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(egress.value, "ipv6_cidr_block", null)
      protocol        = egress.value.protocol
      rule_no         = egress.value.rule_no
      to_port         = egress.value.to_port
    }
  }

  tags = merge(
    { "Name" = "${var.name}-default" },
    var.tags,
  )

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

################################################################################
# Default Route
################################################################################

resource "aws_default_route_table" "default" {

  default_route_table_id = aws_vpc.this.default_route_table_id
  propagating_vgws       = []

  timeouts {
    create = "5m"
    update = "5m"
  }

  tags = merge(
    { "Name" = "${var.name}-default" },
    var.tags,
  )
}
