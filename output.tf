output "vpc_id" {
  value = aws_vpc.main.id
}

output "bastion_public_ip" {
  value       = aws_instance.bastion.public_ip
  description = "踏み台サーバーのパブリックIP（ここにSSH接続）"
}

output "web_private_ip" {
  value       = aws_instance.web.private_ip
  description = "WebサーバーのプライベートIP"
}