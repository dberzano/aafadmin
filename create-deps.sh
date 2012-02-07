#
# create-deps.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Wrapper around the Ruby script to create ALICE dependencies.
#

source /etc/aafrc || exit 1
exec "$AF_PREFIX/bin/create-deps-real.rb"
