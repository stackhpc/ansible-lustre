Tools for working with lustre configuration information.

Under development - only command-line usage is supported, all python names should be considered internal and subject to change.

# Installation:

```shell
sudo yum install -y git epel-release
sudo yum install -y python-pip
sudo pip install -U pip
sudo pip install virtualenv
git clone https://github.com/stackhpc/lustre-tools.git
cd lustre-tools/
virtualenv .venv
. .venv/bin/activate
pip install -U pip
pip install -U -r requirements.txt
```

# Usage
- See `nodemap.py` for controlling nodemap configuration.
- See `lnet.py` for exporting lnet and route configuration.
