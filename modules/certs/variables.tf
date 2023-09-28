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
