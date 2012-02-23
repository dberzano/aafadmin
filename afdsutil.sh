#
# afdsutil.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Wrapper around the ROOT macro to manage datasets.
#

source /etc/aafrc || exit 1
source "$AF_PREFIX/etc/env-alice.sh" --root current || exit 1
source "$AF_PREFIX/etc/af-alien-lib.sh"
AutoAuth
root -l -b "$AF_PREFIX/bin/afdsutil.C+" "$@"
