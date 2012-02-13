#!/bin/bash

#
# af-alien_cp-verify.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# This script downloads a file using alien_cp and verifies the integrity of the
# zip archive and the main .root file.
#
# afdsmgrd variables are ignored: /etc/aafrc variables are used instead.
#

# Source automatic AliEn stuff
source /etc/aafrc || exit 1

# Temporary workaroud until we fix afdsmgrd's setuid BIG problem
# IT REALLY SHOULD BE FIXED **NOW** AND I MEAN IT
if [ `whoami` == 'root' ]; then
  exec su $AF_USER -c "$0 $@"
  exit 1 # not reached
fi

# Source environment for AliEn
source "$AF_PREFIX/etc/env-alice.sh" --root current || exit 1
source "$AF_PREFIX/etc/af-alien-lib.sh" || exit 1

# Exit on error
function Abort() {
  echo "FAIL $Url Reason: $1"
  exit 1
}

# Remove file and empty parents
function DeepRm() {
  local CurDir
  rm -f "$1"
  CurDir=$(dirname "$1")
  while [ "$CurDir" != "/" ]; do
    rmdir "$CurDir" || break
    echo $CurDir
    CurDir=$(dirname "$CurDir")
  done
}

#
# Entry point
#

export Url="$1"
Tree="$2"

PosixPath=${Url%%#*}
Anchor=${Url##*#}
[ "$Anchor" == "$Url" ] && Anchor=''

# They both work. The first one also resolves '.' and '..'
#PosixPath=$(readlink -m "$PosixPath")
PosixPath=$(echo "/$PosixPath" | sed 's#//*#/#g')

# Download file only if it does not exist yet
if [ ! -e "$PosixPath" ]; then

  # Alien path
  AlienPath=${PosixPath:${#AF_SHARED_DATA}}
  AlienPath="alien://$AlienPath"

  # Uncomment for debug
  #echo "Url       => $Url"
  #echo "PosixPath => $PosixPath"
  #echo "Anchor    => $Anchor"
  #echo "Tree      => $Tree"
  #echo "AlienPath => $AlienPath"
  #echo "Command   => alien_cp $AlienPath $PosixPath

  # Perform automatic authentication: exit on failure
  AutoAuth || Abort 'alien-token'

  # Create destination directories
  mkdir -p $(dirname "$PosixPath") || Abort 'mkdir'

  # Copy file using alien_cp
  alien_cp "$AlienPath" "$PosixPath"
  if [ $? != 0 ]; then
    DeepRm "$PosixPath"
    Abort 'alien_cp'
  fi

fi

# Verify the integrity of zip archive, if it is a zip
Ext=${PosixPath##*.}
[ "$Ext" == "$PosixPath" ] && Ext=''
Ext=$(echo "$Ext" | tr '[:upper:]' '[:lower:]')

if [ "$Ext" == 'zip' ]; then
  zip -T "$PosixPath"
  if [ $? != 0 ]; then  # exit code for zip -T failure is 8
    DeepRm "$PosixPath"
    Abort 'zip-damaged'
  fi
fi

# Now, re-assemble the anchor and check the file with ROOT
TempOut=$(mktemp /tmp/af-alien_cp-verify-root.XXXXX)
root.exe -b -q \
  "$ROOTSYS/etc/proof/afdsmgrd-macros/Verify.C"'("file://'$PosixPath\#$Anchor'", "'$Tree'")' 2>&1 | tee -a $TempOut

# Decide whether to remove the file or not: if integrity check fails, file
# should be removed to save space
grep '^OK ' $TempOut > /dev/null || DeepRm "$PosixPath"

# Remove output file
rm -f $TempOut
