#!/bin/sh
# $Id$

set -e

# set thisdir
THISDIR="$(readlink -f "$(dirname "$0")")"

# path
TRUNK_ROOT="$(readlink -f "$THISDIR/../../trunk")"
UPLOAD_ROOT="$(readlink -f "$THISDIR/../../temp/upload")"
RSYNC=${RSYNC:-rsync}
RSYNC_OPT_MAIN="-avz --rsh=ssh --exclude=*~ --exclude=.svn --exclude=log"
RSYNC_OPT_TRUNK="${RSYNC_OPT_MAIN} --exclude=common --exclude=tools --exclude=web --exclude=filelist.cgi*"

# start
cd "${UPLOAD_ROOT}"

echo "updating..."
svn up
svnversion . > .svnversion.new
if cmp .svnversion .svnversion.new 2>&1 > /dev/null; then
  rm .svnversion.new
else
  mv .svnversion.new .svnversion
fi

echo "uploading..."
. ${THISDIR}/.uploadto
for host in ${HOSTS}; do
  # don't quote ${RSYNC_OPT}!
  ${RSYNC} ${RSYNC_OPT_TRUNK} . ${host}:/home/topia/tiarra
#  ${RSYNC} ${RSYNC_OPT_MAIN} ${TRUNK_ROOT}/common ${TRUNK_ROOT}/${host} ${host}:/home/topia/tiarra
  ${RSYNC} ${RSYNC_OPT_MAIN} ${TRUNK_ROOT}/common ${host}:/home/topia/tiarra
  ${RSYNC} ${RSYNC_OPT_MAIN} ${TRUNK_ROOT}/confs/run ${TRUNK_ROOT}/confs/.tiarrarc ${TRUNK_ROOT}/confs/common ${TRUNK_ROOT}/confs/${host} ${host}:/home/topia/tiarra/confs || :
#  ${RSYNC} ${RSYNC_OPT_MAIN} ${TRUNK_ROOT}/confs/common ${host}:/home/topia/tiarra/confs
done
