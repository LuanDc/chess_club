output "instance_public_ip" {
  description = "Public IP address of the chess server"
  value       = aws_instance.chess_server.public_ip
}

output "instance_id" {
  description = "ID of the chess server EC2 instance"
  value       = aws_instance.chess_server.id
}

output "ssh_command" {
  description = "SSH command to connect as the ubuntu user"
  value       = "ssh ubuntu@${aws_instance.chess_server.public_ip}"
}

output "ssh_command_deploy" {
  description = "SSH command to connect as the deploy user"
  value       = "ssh deploy@${aws_instance.chess_server.public_ip}"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.chess.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.chess_public.id
}
