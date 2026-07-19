data "aws_ami" "arch" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["arch-linux-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
