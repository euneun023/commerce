resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "terraform-01"
  }
}

resource "aws_subnet" "pub_2a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-northeast-2a"
  map_public_ip_on_launch = false
  tags = {
    Name = "terraform-01-pub-2a"
   # "Kubernetes.io/role/elb" = "1"
   # "Kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "shared"
  }
}

resource "aws_subnet" "pub_2c" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-northeast-2c"
  map_public_ip_on_launch = false
  tags = {
    Name = "terraform-01-pub-2c"
   # "kubernetes.io/role/elb" = "1"
   # "Kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "shared"
     }
}

resource "aws_subnet" "pvt_2a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.101.0/24"
  availability_zone = "ap-northeast-2a"
  tags = {
    Name = "terraform-01-pvt-2a"
   # "Kubernetes.io/role/internal-elb" = "1"
   # "Kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "shared"
  }
}

resource "aws_subnet" "pvt_2c" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.102.0/24"
  availability_zone = "ap-northeast-2c"
  tags = {
    Name = "terraform-01-pvt-2c"
   # "Kubernetes.io/role/internal-elb" = "1"
   # "Kubernetes.io/cluster/${aws_eks_cluster.main.name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "terraform-01-igw"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  lifecycle {
    create_before_destroy = true
  }
}

#nat_gw 한개, pub_2a
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.pub_2a.id

  tags = {
    Name = "terraform-01-natgw"
  } 
  depends_on = [aws_internet_gateway.igw]
}

#rtb - pub - igw
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "terraform-01-rtb-pub"
  }
}

resource "aws_route_table_association" "pub_2a" {
  subnet_id = aws_subnet.pub_2a.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_2c" {
  subnet_id = aws_subnet.pub_2c.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route" "pub_igw" {
  route_table_id = aws_route_table.pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
}

#rtb - pvt - nat
resource "aws_route_table" "pvt" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "terraform-01-rtb-pvt"
  }
}

resource "aws_route_table_association" "pvt_2a" {
  subnet_id = aws_subnet.pvt_2a.id
  route_table_id = aws_route_table.pvt.id
}

resource "aws_route_table_association" "pvt_2c" {
  subnet_id = aws_subnet.pvt_2c.id
  route_table_id = aws_route_table.pvt.id
}

resource "aws_route" "pvt_nat" {
  route_table_id = aws_route_table.pvt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat.id
}

resource "aws_ecr_repository" "api_server" {
  name = "api-server"
  image_tag_mutability = "MUTABLE"

  lifecycle {
    prevent_destroy = true
  }
  image_scanning_configuration {
    scan_on_push = true
  }
}
