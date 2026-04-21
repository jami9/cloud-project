#!/usr/bin/env bash
# MicroStack OpenStack RC file (corrected for SSL and auth)

export OS_AUTH_URL=http://192.168.56.101:5000/v3
export OS_PROJECT_ID=f5dd211592d1436fb7e0a9fe58e5c8e4
export OS_PROJECT_NAME="admin"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_ID="default"
unset OS_TENANT_ID
unset OS_TENANT_NAME
export OS_USERNAME="admin"

# Prompt for password securely
echo "Please enter your OpenStack Password for project $OS_PROJECT_NAME as user $OS_USERNAME: "
read -sr OS_PASSWORD_INPUT
export OS_PASSWORD=$OS_PASSWORD_INPUT

export OS_REGION_NAME="microstack"
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3

# Ignore SSL certs (necessary for MicroStack self-signed cert)
export OS_INSECURE=1
