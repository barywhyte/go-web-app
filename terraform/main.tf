terraform {
  backend "s3" {
    bucket = "be.seun.terraform"
    key    = "terraform/state"
    region = "us-east-1"
  }
}

data "aws_region" "current" {}


# create VPC

module "vpc_network" {
    source = "./modules/network/"
    vpc_cidr = "192.168.0.0/16"
    public_subnet_cidr = "192.168.1.0/24"
    public_subnet_az = "us-east-1a"
    public_subnet_map_ip = true

    private_subnet_cidr = "192.168.2.0/24"
    private_subnet_az = "us-east-1b"
    private_subnet_map_ip = true

}

module "eks_cluster" {
    source = "./modules/eks"
    
}