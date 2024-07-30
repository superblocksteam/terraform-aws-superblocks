#################################
# Security group with name_prefix
#################################
resource "aws_security_group" "this_name_prefix" {
  count = 1
  name_prefix            = "${var.name}-"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = false

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
  )

  lifecycle {
    create_before_destroy = true
  }

  timeouts {
    create = var.create_timeout
    delete = var.delete_timeout
  }
}

resource "aws_security_group_rule" "ingress_with_source_security_group_id" {
  count = length(var.ingress_with_source_security_group_id)

  security_group_id = aws_security_group.this_name_prefix[0].id
  type              = "ingress"

  source_security_group_id = var.ingress_with_source_security_group_id[count.index]["source_security_group_id"]
  prefix_list_ids          = var.ingress_prefix_list_ids
  description = lookup(
    var.ingress_with_source_security_group_id[count.index],
    "description",
    "Ingress Rule",
  )

  from_port = lookup(
    var.ingress_with_source_security_group_id[count.index],
    "from_port",
  )
  to_port = lookup(
    var.ingress_with_source_security_group_id[count.index],
    "to_port",
  )
  protocol = lookup(
    var.ingress_with_source_security_group_id[count.index],
    "protocol",
  )
}


resource "aws_security_group_rule" "ingress_with_cidr_blocks" {
  count = length(var.ingress_with_cidr_blocks)

  security_group_id = aws_security_group.this_name_prefix[0].id
  type              = "ingress"

  cidr_blocks = compact(split(
    ",",
    lookup(
      var.ingress_with_cidr_blocks[count.index],
      "cidr_blocks",
      join(",", var.ingress_cidr_blocks),
    ),
  ))
  prefix_list_ids = var.ingress_prefix_list_ids
  description = lookup(
    var.ingress_with_cidr_blocks[count.index],
    "description",
    "Ingress Rule",
  )

  from_port = lookup(
    var.ingress_with_cidr_blocks[count.index],
    "from_port",
  )
  to_port = lookup(
    var.ingress_with_cidr_blocks[count.index],
    "to_port",
  )
  protocol = lookup(
    var.ingress_with_cidr_blocks[count.index],
    "protocol",
  )
}


resource "aws_security_group_rule" "egress_with_cidr_blocks" {
  count = length(var.egress_with_cidr_blocks)

  security_group_id = aws_security_group.this_name_prefix[0].id
  type              = "egress"

  cidr_blocks = compact(split(
    ",",
    lookup(
      var.egress_with_cidr_blocks[count.index],
      "cidr_blocks",
      join(",", var.egress_cidr_blocks),
    ),
  ))
  prefix_list_ids = var.egress_prefix_list_ids
  description = lookup(
    var.egress_with_cidr_blocks[count.index],
    "description",
    "Egress Rule",
  )

  from_port = lookup(
    var.egress_with_cidr_blocks[count.index],
    "from_port",
  )
  to_port = lookup(
    var.egress_with_cidr_blocks[count.index],
    "to_port",
  )
  protocol = lookup(
    var.egress_with_cidr_blocks[count.index],
    "protocol",
  )
}
