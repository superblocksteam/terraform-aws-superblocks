variable "tags" {
  type    = map(string)
  default = {}
}

variable "zone_name" {
  type = string
}

variable "record_name" {
  type    = string
  default = "agent"
}

variable "private_zone" {
  type    = bool
  default = false
}

variable "vpc_id" {
  type    = string
  default = null
}
