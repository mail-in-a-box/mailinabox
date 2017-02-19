# Automatic installation in AWS using terraform

Assuming you have an Amazon Web Services account and you've registered your domain [through their registrar](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html), you can use terraform to automatically create a mailinabox, complete with an EBS-backed volume to take advantage of immutable infrastructure. 

First, [install terraform](https://www.terraform.io/intro/getting-started/install.html). Then, create a new file in this folder titled `terraform.tfvars` with the following information:

```
access_key = ""
secret_key = ""
region = "us-east-1"
domain_name = ""
email_address = ""
email_password = ""
```

Next, create an ssh keypair associated with the miab.

```
ssh-keygen -f ~/.ssh/miab
aws ec2 import-key-pair --key-name miab-key \
  --public-key-material file://$HOME//.ssh/miab.pub
```

Then, type in `terraform apply` and wait about 15 minutes. Then, follow the [remaining instructions here](https://mailinabox.email/guide.html#admin) to set up the SSL certificates.
