resource "aws_vpc" "this" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "public" {
  count                   = var.create_vpc ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route_table" "rt" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route" "route" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.rt[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw[0].id
}

resource "aws_route_table_association" "assoc" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.rt[0].id
}