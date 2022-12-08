variable "name_prefix" {
  type    = string
  default = "superblocks"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "cidr_block" {
  type    = string
  default = "10.0.0.0/20"
}

variable "public_subnets" {
  type = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
  ]
}

variable "private_subnets" {
  type = list(string)
  default = [
    "10.0.11.0/24",
    "10.0.12.0/24",
    "10.0.13.0/24",
  ]
}
