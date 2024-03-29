terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
# AWS Hesabinin AccountID'sini cekmek icin kullaniyoruz.
data "aws_caller_identity" "current" {}


data "aws_region" "current" {
    name="us-east-1"  
}


##!!!!   Warning! The branch name of the repo on GitHub has to be master. It doesn't work when it's main. 
## If it's master, fix it manually.
locals {
  github-repo= "https://github.com/cagatayakk/phonebook_swarm.git"
  github-file-url= "https://raw.githubusercontent.com/cagatayakk/phonebook_swarm/master/"
}

# userdata'yi bu sekilde girerek icinde terraform referanslari kullanabiliyoruz.
data "template_file" "leader-master" {
  template = <<EOF
    #! /bin/bash
    yum update -y
    hostnamectl set-hostname Leader-Manager
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    docker swarm init
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.ecr-repo.repository_url}
    docker service create \
      --name=viz \
      --publish=8080:8080/tcp \
      --constraint=node.role==manager \
      --mount=type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
      dockersamples/visualizer
    yum install git -y
    #docker build --force-rm -t "${aws_ecr_repository.ecr-repo.repository_url}:latest" ${local.github-repo}
    docker build --force-rm -t "${aws_ecr_repository.ecr-repo.repository_url}:latest" ${local.github-repo}#main
    docker push "${aws_ecr_repository.ecr-repo.repository_url}:latest"
    mkdir -p /home/ec2-user/phonebook
    cd /home/ec2-user/phonebook && echo "ECR_REPO=${aws_ecr_repository.ecr-repo.repository_url}" > .env
    # -o : local'de dosyanin adini docker-compose.yaml yap
    curl -o "docker-compose.yml" -L ${local.github-file-url}docker-compose.yml
    curl -o "init.sql" -L ${local.github-file-url}init.sql
    # docker-compose config komutu dogru calisirsa ciktisini pipe'in saginda girdi olarak kullanirim.
    # --with-registry-auth  : kimlik dogrulama bilgilerimi gönder demek.
    docker-compose config | docker stack deploy --with-registry-auth -c - phonebook
EOF
}


data "template_file" "manager" {
  template = <<EOF
    #! /bin/bash
    yum update -y
    hostnamectl set-hostname Manager
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    yum install python3 -y
    amazon-linux-extras install epel -y
    yum install python-pip -y
    pip install ec2instanceconnectcli
    aws ec2 wait instance-status-ok --instance-ids ${aws_instance.docker-machine-leader-manager.id}
    # eval  parantez icindeki komutlari terminalde bizim icin girer.
    eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
    --region ${data.aws_region.current.name} ${aws_instance.docker-machine-leader-manager.id} docker swarm join-token manager | grep -i 'docker')"
  EOF
}

data "template_file" "worker" {
  template = <<EOF
    #! /bin/bash
    yum update -y
    hostnamectl set-hostname Worker
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # uninstall aws cli version 1
    rm -rf /bin/aws
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    yum install python3 -y
    amazon-linux-extras install epel -y
    yum install python-pip -y
    pip install ec2instanceconnectcli
    aws ec2 wait instance-status-ok --instance-ids ${aws_instance.docker-machine-leader-manager.id}
    eval "$(mssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no  \
     --region ${data.aws_region.current.name} ${aws_instance.docker-machine-leader-manager.id} docker swarm join-token worker | grep -i 'docker')"
  EOF
}





resource "aws_ecr_repository" "ecr-repo" {
  name = "repo-204/phonebook-app"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
  # bu komut ile dolu olan repoyu force uygulayarak sileriz. Manuel olarak image'lari repodan silmeye gerek kalmaz.
  force_delete = true
}

variable "myami" {
  default = "ami-05fa00d4c63e32376"
}
variable "instancetype" {
  default = "t2.micro"
}
variable "mykey" {
  default = "cagatayakk"
}

resource "aws_instance" "docker-machine-leader-manager" {
  ami = var.myami
  instance_type = var.instancetype
  key_name = var.mykey
  root_block_device {
    volume_size = 16
  }
  vpc_security_group_ids = [aws_security_group.tf-docker-sec-gr.id]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  user_data = data.template_file.leader-master.rendered
  tags = {
    Name = "Docker-Swarm-Leader-Manager"
  }
}

resource "aws_instance" "docker-machine-managers" {
  ami             = var.myami
  instance_type   = var.instancetype
  key_name        = var.mykey
  vpc_security_group_ids = [aws_security_group.tf-docker-sec-gr.id]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  count = 2
  user_data = data.template_file.manager.rendered
  tags = {
    Name = "Docker-Swarm-Manager-${count.index + 1}"
  }
  depends_on = [aws_instance.docker-machine-leader-manager]
}

resource "aws_instance" "docker-machine-workers" {
  ami             = var.myami
  instance_type   = var.instancetype
  key_name        = var.mykey
  vpc_security_group_ids = [aws_security_group.tf-docker-sec-gr.id]
  iam_instance_profile = aws_iam_instance_profile.ec2ecr-profile.name
  count = 2
  user_data = data.template_file.worker.rendered
  tags = {
    Name = "Docker-Swarm-Worker-${count.index + 1}"
  }
  depends_on = [aws_instance.docker-machine-leader-manager]
}

# kendini tekrar eden ingress bloklari ldugu icin dynamic ingress kullaniyoruz.
variable "sg-ports" {
  default = [80, 22, 2377, 7946, 8080]  
}

resource "aws_security_group" "tf-docker-sec-gr" {
  name = "docker-swarm-sec-gr-proje204"
  tags = {
    Name = "swarm-sec-gr"
  }
  dynamic "ingress" {
    for_each = var.sg-ports
    content {
      from_port = ingress.value
      to_port = ingress.value
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  ingress {
    from_port = 7946
    protocol = "udp"
    to_port = 7946
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 4789
    protocol = "udp"
    to_port = 4789
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2fulltoecr" {
  name = "ec2roletoecrproject204"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  ## Burada ec2-connect-cli metodunu kullanabilmek icin inline policy tanimliyoruz. Bu metod ile instanceid araciligi ile olusacak makinalara pem key'i 
  ## kopyalamadan baglanti saglamak icin kullaniyoruz. 91. satirda bunu pip ile yükledik
  inline_policy {
    name = "my_inline_policy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          "Effect" : "Allow",
          "Action" : "ec2-instance-connect:SendSSHPublicKey",
          "Resource" : "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          "Condition" : {
            "StringEquals" : {
              "ec2:osuser" : "ec2-user"
            }
          }
        },
        {
          "Effect" : "Allow",
          "Action" : "ec2:DescribeInstances",
          "Resource" : "*"
        }
      ]
    })
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"]
}

# makinalara Rolleri atamak icin profile tanimlamamiz gerekir.
resource "aws_iam_instance_profile" "ec2ecr-profile" {
  name = "swarmprofileproje204"
  role = aws_iam_role.ec2fulltoecr.name
}

output "leader-manager-public-ip" {
  value = aws_instance.docker-machine-leader-manager.public_ip
}

output "website-url" {
  value = "http://${aws_instance.docker-machine-leader-manager.public_ip}"
}

output "viz-url" {
  value = "http://${aws_instance.docker-machine-leader-manager.public_ip}:8080"
}

output "manager-public-ip" {
  value = aws_instance.docker-machine-managers.*.public_ip
}

output "worker-public-ip" {
  value = aws_instance.docker-machine-workers.*.public_ip
}

output "ecr-repo-url" {
  value = aws_ecr_repository.ecr-repo.repository_url
}








#docker build --force-rm -t "232481028428.dkr.ecr.us-east-1.amazonaws.com/repo-204/phonebook-app:latest" https://github.com/cagatayakk/phonebook_swarm.git


#aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 232481028428.dkr.ecr.us-east-1.amazonaws.com/repo-204/phonebook-app
