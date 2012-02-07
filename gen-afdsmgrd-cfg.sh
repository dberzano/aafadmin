#!/bin/bash

#
# gen-afdsmgrd-cfg.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Generates configuration for afdsmgrd from a Cheetah template and environment
# variables.
#

# Load environment variables
source /etc/aafrc || exit 1

# Datasets directory
export TPL_PROOF_DATASETS="$AF_PREFIX/var/proof/datasets"

# Move to configuration directory
cd "$AF_PREFIX"/etc/proof || exit 1

# Process template using Cheetah (a backup copy will be made)
echo "Inside directory $PWD"

echo 'Processing configuration file'
cheetah fill --env --oext conf afdsmgrd.tmpl || exit $?

echo 'Processing environment file'
cheetah fill --env --oext sh afdsmgrd_env.tmpl || exit $?
