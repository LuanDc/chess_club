output "instance_public_ip" {
  description = "Public IP address of the chess server"
  value       = oci_core_instance.chess_server.public_ip
}

output "instance_id" {
  description = "OCID of the chess server instance"
  value       = oci_core_instance.chess_server.id
}

output "ssh_command" {
  description = "SSH command to connect as the ubuntu user"
  value       = "ssh ubuntu@${oci_core_instance.chess_server.public_ip}"
}

output "ssh_command_deploy" {
  description = "SSH command to connect as the deploy user"
  value       = "ssh deploy@${oci_core_instance.chess_server.public_ip}"
}

output "vcn_id" {
  description = "OCID of the Virtual Cloud Network"
  value       = oci_core_vcn.chess.id
}

output "subnet_id" {
  description = "OCID of the public subnet"
  value       = oci_core_subnet.chess_public.id
}
