variable "name_prefix" {
  type    = string
  default = "superblocks"
}

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

variable "alias_name" {
  type = string
}

variable "alias_zone_id" {
  type = string
}
