# Lustre example

## Create Infrastructure

Download the latest and unzip it:
https://www.terraform.io/downloads.html

For example:

    export terraform_version="0.12.20"
    wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
    unzip terraform_${terraform_version}_linux_amd64.zip

Now you can get Terraform to create the infrastructure:

    cd terraform/examples/slurm
    terraform init
    terraform plan
    terraform apply

## Install OpenHPC Slurm with Ansible

You may find this useful to run the ansible-playbook command below:

    cd ansible
    virtualenv .venv
    . .venv/bin/activate
    pip install -U pip
    pip install -U -r requirements.txt
    #ansible-galaxy install -r requirements.yml

You can create a cluster by doing:

    ansible-playbook main.yml -i inventory
