output "cluster_name" {
  value = local.cluster_name
}

output "head_node_public_ip" {
  value = aws_instance.head[*].public_ip
}

output "head_node_private_ip" {
  value = aws_instance.head[*].private_ip
}

output "ollama_api_endpoint" {
  description = "Ollama API endpoint via ALB"
  value       = "http://${aws_lb.ollama.dns_name}:11434"
}

output "qdrant_endpoint" {
  description = "Qdrant HTTP endpoint"
  value       = var.vectordb_node_count > 0 ? "http://${aws_instance.vectordb[0].private_ip}:6333" : "No vector DB deployed"
}

output "worker_spot_instance_ids" {
  value = aws_spot_instance_request.worker[*].spot_instance_id
}

output "ssh_key_name" {
  value = aws_key_pair.cluster.key_name
}

output "ssh_private_key" {
  description = "SSH private key for cluster access"
  value       = tls_private_key.cluster.private_key_pem
  sensitive   = true
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "security_group_id" {
  value = aws_security_group.cluster.id
}
