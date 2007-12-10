#!/bin/sh
# $Id$

set -e

# set thisdir
THISDIR="$(readlink -f "$(dirname "$0")")"

# path
SVNROOT='file:///usr/minetools/svnroot/tiarra'
SVNROOT_VENDOR="$SVNROOT/vendor"
TRUNK_ROOT="$(readlink -f "$THISDIR/../../temp/merge")"
MERGED_TAG_FILE="${TRUNK_ROOT}/status/merged-tag"
IMPORT_TAG_PREFIX=''

# start
merged_tag_last="$(cat "$MERGED_TAG_FILE")"

vendor_tag_now="$(svn ls "${SVNROOT_VENDOR}" |
    sed -e '/\/$/!d' -e 's,/$,,' \
	-e "/^${IMPORT_TAG_PREFIX}/!d" \
	-e '/^current$/d' | sort -r | head -1)"

cd "${TRUNK_ROOT}"

echo "updating"
svn up
if [ "${merged_tag_last}" = "${vendor_tag_now}" ]; then
  echo "merging... same tag (${vendor_tag_now}). skip."
else
  echo "merging... ${merged_tag_last} -> ${vendor_tag_now}"
  svn merge "${SVNROOT_VENDOR}/${merged_tag_last}" "${SVNROOT_VENDOR}/${vendor_tag_now}"
  echo -n "${vendor_tag_now}" > "${MERGED_TAG_FILE}"
fi
svn commit -m '* merge from vendor repository.'
