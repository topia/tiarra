#!/bin/sh
# $Id$
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.

for i in "$@"; do
  echo ". ${i}" >> .tiarrarc-once
done

