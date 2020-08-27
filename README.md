Third-I installation script
===========================

This script works on top of the provided StereoPi image.

Run it using ssh:

```
# you first need to add an SSH key that has access to the private repositories
ssh-add ~/.ssh/id_rsa

ssh -A root@stereopi.lan < install.sh
```
