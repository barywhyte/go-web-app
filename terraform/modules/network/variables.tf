variable "vpc_cidr" {}

variable region {
    default = "us-east-1"
}


variable "public_subnet_cidr"{
    type = string
}

variable "public_subnet_az"{
    type = string
}

variable "public_subnet_map_ip"{
    type = bool
}

variable "private_subnet_cidr"{
    type = string
}

variable "private_subnet_az"{
    type = string
}

variable "private_subnet_map_ip"{
    type = bool
}