#!/bin/bash

#
# gen-proof-cfg.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Generates the PROOF main configuration file from a Cheetah template and
# environment variables.
#

# Load environment variables
source /etc/aafrc || exit 1

# Prefix for ROOT packages
export TPL_ROOT_PREFIX=$AF_PACK_DIR/VO_ALICE/ROOT

# ROOT versions available, separated by a pipe
export TPL_ROOT_VER=$(
  cd "$TPL_ROOT_PREFIX" ;
  ls -1d */ | cut -d/ -f1 | \
  while read RootVer ; do
    echo -n "$RootVer|"
  done)

# Move to configuration directory
cd "$AF_PREFIX"/etc/proof || exit 1

# Process template using Cheetah (a backup copy will be made)
echo "Inside directory $PWD"
exec cheetah fill --env --oext cf prf-main.tmpl
