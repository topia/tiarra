#!/bin/sh

set -e

if [ -n "$RUN_GROUP" ]; then
  : ${RUN_GID:?should be set RUN_GID if RUN_GROUP specified}
  if getent group "$RUN_GROUP" > /dev/null 2>&1; then
    groupmod -g "$RUN_GID" "$RUN_GROUP"
  else
    groupadd -g "$RUN_GID" "$RUN_GROUP"
  fi
fi
if [ -n "$RUN_USER" ]; then
  : ${RUN_UID:?should be set RUN_UID if RUN_USER specified}
  if getent passwd "$RUN_USER" > /dev/null 2>&1; then
    usermod -d /nonexistent ${RUN_GROUP:+-g} ${RUN_GROUP:+"$RUN_GROUP"} -u "$RUN_UID" "$RUN_USER" > /dev/null 2>&1
  else
    useradd --no-create-home -d /nonexistent ${RUN_GROUP:+-g} ${RUN_GROUP:+"$RUN_GROUP"} -u "$RUN_UID" "$RUN_USER"
  fi
else
  RUN_USER="$(id -un)"
fi

TIARRA_DIR="$(dirname "$(readlink -f "$0")")"

env
chpst -u "$RUN_USER${RUN_GROUP:+:$RUN_GROUP}" perl "$TIARRA_DIR/tiarra" --show-env
cat <<END
USER: $RUN_USER
${RUN_GROUP:+GROUP: $RUN_GROUP
}WORK DIR: $TIARRA_WORK_DIR
TIARRA CONFIG: $TIARRA_CONFIG
ADDITIONAL ARGS: $@
END

[ -n "$TIARRA_WORK_DIR" ] && cd "$TIARRA_WORK_DIR"
exec chpst -u "$RUN_USER${RUN_GROUP:+:$RUN_GROUP}" perl "$TIARRA_DIR/tiarra" ${TIARRA_CONFIG:+--config="$TIARRA_CONFIG"} "$@"
