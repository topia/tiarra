#!/bin/sh
# $Id$
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.

# FIXME: fixed string
REDIR_STDOUT=${REDIR_STDOUT:-errlog.stdout}
REDIR_STDERR=${REDIR_STDERR:-errlog.stderr}
rm -f "${REDIR_STDOUT}" "${REDIR_STDERR}"
