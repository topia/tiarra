#!/bin/sh
# $Id$
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.

# FIXME: fixed string
REDIR_STDOUT="${REDIR_STDOUT:->errlog.stdout}"
REDIR_STDERR="${REDIR_STDERR:->errlog.stderr}"
for i in "${REDIR_STDOUT}" "${REDIR_STDERR}"; do
  case "$i" in
    \&*|-) ;;
    *)
      rm -f "${i#>}"
      ;;
  esac
done
