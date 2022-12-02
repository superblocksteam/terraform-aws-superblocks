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
  default = "8020"
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
