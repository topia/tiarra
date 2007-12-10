#!/bin/sh
# $Id$
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.

LAZY_EXECUTE="${LAZY_EXECUTE}"'
for i in "${REDIR_STDOUT}" "${REDIR_STDERR}"; do
  case "$i" in
    \&*|-) ;;
    *)
      rm -f "${i#>}"
      ;;
  esac
done
'
