#! /usr/bin/env bash

# Sets up a master Jenkins server and associated machinery like
# Zuul, JJB, Gearman, etc.

set -e

THIS_DIR=`pwd`

DATA_REPO_INFO_FILE=$THIS_DIR/.data_repo_info
DATA_PATH=$THIS_DIR/data
OSEXT_PATH=$THIS_DIR/os-ext-testing
OSEXT_REPO=https://github.com/dani4571/os-ext-testing
PUPPET_MODULE_PATH="--modulepath=$OSEXT_PATH/puppet/modules:/root/config/modules:/etc/puppet/modules"


if [[ ! -e $DATA_PATH ]]; then
    echo "Enter the URI for the location of your config data repository. Example: https://github.com/jaypipes/os-ext-testing-data"
    read data_repo_uri
    if [[ "$data_repo_uri" == "" ]]; then
        echo "Data repository is required to proceed. Exiting."
        exit 1
    fi
    git clone $data_repo_uri $DATA_PATH
fi

if [[ "$PULL_LATEST_DATA_REPO" == "1" ]]; then
    echo "Pulling latest data repo master."
    cd $DATA_PATH; git checkout master && git pull; cd $THIS_DIR;
fi

# Pulling in variables from data repository
. $DATA_PATH/nodepool_vars.sh

# Validate there is a Nodepool SSH key pair in the data repository
if [[ -z $NODEPOOL_SSH_KEY_PATH ]]; then
    echo "Expected to find NODEPOOL_SSH_KEY_PATH in $DATA_PATH/vars.sh. Please correct. Exiting."
    exit 1
elif [[ ! -e "$DATA_PATH/$NODEPOOL_SSH_KEY_PATH" ]]; then
    echo "Expected to find Jenkins SSH key pair at $DATA_PATH/$NODEPOOL_SSH_KEY_PATH, but wasn't found. Please correct. Exiting."
    exit 1
else
    echo "Using Jenkins SSH key path: $DATA_PATH/$NODEPOOL_SSH_KEY_PATH"
    NODEPOOL_SSH_PRIVATE_KEY_CONTENTS=`sudo cat $DATA_PATH/$NODEPOOL_SSH_KEY_PATH`
    NODEPOOL_SSH_PUBLIC_KEY_CONTENTS=`sudo cat $DATA_PATH/$NODEPOOL_SSH_KEY_PATH.pub`
fi



PUBLISH_HOST=${PUBLISH_HOST:-localhost}

APACHE_SSL_CERT_FILE=`cat $APACHE_SSL_ROOT_DIR/new.cert.cert`
APACHE_SSL_KEY_FILE=`cat $APACHE_SSL_ROOT_DIR/new.cert.key`

CLASS_ARGS="jenkins_api_key => '$JENKINS_API_KEY', "
CLASS_ARGS="$CLASS_ARGS nodepool_ssh_public_key => '$NODEPOOL_SSH_PUBLIC_KEY_CONTENTS', nodepool_ssh_private_key => '$NODEPOOL_SSH_PRIVATE_KEY_CONTENTS', "
CLASS_ARGS="$CLASS_ARGS jenkins_api_user => '$JENKINS_API_USER', "
CLASS_ARGS="$CLASS_ARGS jenkins_api_key => '$JENKINS_API_KEY', "
CLASS_ARGS="$CLASS_ARGS rackspace_username => '$RACKSPACE_USERNAME', "
CLASS_ARGS="$CLASS_ARGS rackspace_password => '$RACKSPACE_PASSWORD', "
CLASS_ARGS="$CLASS_ARGS mysql_root_password => '$MYSQL_ROOT_PASSWORD', "
CLASS_ARGS="$CLASS_ARGS mysql_password => '$MYSQL_PASSWORD', "
#CLASS_ARGS="$CLASS_ARGS publish_host => '$PUBLISH_HOST', "
#CLASS_ARGS="$CLASS_ARGS data_repo_dir => '$DATA_PATH', "
#CLASS_ARGS="$CLASS_ARGS url_pattern => '$URL_PATTERN', "

sudo puppet apply --verbose $PUPPET_MODULE_PATH -e "class {'os_ext_testing::nodepool_test': $CLASS_ARGS }"
