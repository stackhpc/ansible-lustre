# ansible-lustre

Ansible to configure Lustre, with a terraform based example usage.

## Create infrastructure with terraform

Download the 0.12.x release and unzip it:
https://www.terraform.io/downloads.html

Install doing things like this:

    export terraform_version="0.12.20"
    wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
    unzip terraform_${terraform_version}_linux_amd64.zip

From Horizon download a clouds.yaml file and put it in:

    terraform/examples/slurm/clouds.yaml

Now you can get Terraform to create the infrastructure:

    cd terraform/examples/slurm
    terraform init
    terraform plan
    terraform apply

## Install Lustre with Ansible

You may find this useful to run the ansible-playbook command below:

    cd ansible
    virtualenv .venv
    . .venv/bin/activate
    pip install -U pip
    pip install -U -r requirements.txt

You can create a cluster by doing:

    ansible-playbook main.yml -i inventory

Note that the inventory file is a symlink to the output of terraform.
