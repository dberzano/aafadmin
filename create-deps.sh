#
# create-deps.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Wrapper around the Ruby script to create ALICE dependencies.
#

source /etc/aafrc || exit 1
exec "`dirname "$0"`"/create-deps-real.rb "$@"
