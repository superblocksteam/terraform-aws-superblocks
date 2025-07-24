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

variable "private_zone" {
  type    = bool
  default = false
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "container_port_http" {
  type    = number
  default = "8080"
}

variable "container_port_grpc" {
  type    = number
  default = "8081"
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

variable "ssl_enable" {
  type    = bool
  default = true
}

variable "create_dns" {
  type    = bool
  default = false
}

variable "zone_name" {
  type    = string
  default = null
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
    },
    {
      from_port   = 8443
      to_port     = 8443
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

variable "target_group_idle_timeout" {
  type        = number
  default     = 60
  description = "Idle timeout (in seconds) for the ALB target group. Increase this for long-lived connections."
}
