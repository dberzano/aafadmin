#!/bin/bash

#
# gen-proof-cfg.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Generates the PROOF main configuration file from a Cheetah template and
# environment variables.
#

export TPL_ROOT_PREFIX=$AF_PACK_DIR/VO_ALICE/ROOT

export TPL_ROOT_VER=$(
  cd "$TPL_ROOT_PREFIX" ;
  ls -1d */ | cut -d/ -f1 | \
  while read RootVer ; do
    echo -n "$RootVer|"
  done)

exec cheetah fill --env --oext cf prf-main.tmpl
