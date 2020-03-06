Tools for working with lustre configuration information.

Very much a work in progress. At the moment only command-line usage is really supported, all names should be considered subject to change.

Installation:

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