#!/usr/bin/env zsh

if [ "$#" -ne 1 ]; then
  length=32
else
  length="$1"
fi

openssl rand -base64 "$length"
