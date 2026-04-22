output "vpc_id" {
  value = aws_vpc.this[0].id
}

output "public_subnet_id" {
  value = aws_subnet.public[0].id
}