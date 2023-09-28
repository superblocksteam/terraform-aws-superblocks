variable "name_prefix" {
  type    = string
  default = "superblocks"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "internal" {
  type = bool
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "container_port" {
  type    = number
  default = "8080"
}

variable "listener_port" {
  type    = number
  default = "443"
}

variable "listener_protocol" {
  type    = string
  default = "HTTPS"
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "create_dns" {
  type    = bool
  default = false
}

variable "zone_name" {
  type = string
}

variable "record_name" {
  type    = string
  default = "agent"
}

variable "dns_ttl" {
  type    = number
  default = "120"
}

variable "create_sg" {
  type    = bool
  default = true
}

variable "sg_ingress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

variable "sg_egress_with_cidr_blocks" {
  type = list(map(string))
  default = [
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "All Egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}
