#!/bin/sh
# $Id$

set -e

# set thisdir
THISDIR="$(readlink -f "$(dirname "$0")")"

# path
SVNROOT='file:///usr/minetools/svnroot/tiarra/vendor'
IMPORT_AS='current'
WORKING_ROOT="$(readlink -f "$THISDIR/../../vendor/cvs")"
IMPORT_CVS="${WORKING_ROOT}/master"
IMPORT_WORKING="${WORKING_ROOT}/temp"
IMPORT_TAG_PREFIX=''

# prog
SVN_LOAD_DIRS='/usr/opt/bin/svn_load_dirs'

# start
import_tag_current="${IMPORT_TAG_PREFIX}`date '+%Y%m%d-%H%M%S'`"
temp_name="temp-${import_tag_current}.$$"

echo "current import tag: $import_tag_current"

cd ${IMPORT_CVS}
cvs -z5 -q up -dP

mkdir -p "${IMPORT_WORKING}"
cp -al "${IMPORT_CVS}" "${IMPORT_WORKING}/${temp_name}"
cd "${IMPORT_WORKING}"

# clean-up CVS dir
find "${temp_name}" -name CVS -type d -print0 | xargs -0 rm -rf

${SVN_LOAD_DIRS} -t "${import_tag_current}" "${SVNROOT}" "${IMPORT_TAG_PREFIX}current" "${temp_name}"

rm -rf "${temp_name}"
