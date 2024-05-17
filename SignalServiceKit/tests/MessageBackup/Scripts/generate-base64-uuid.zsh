#!/usr/bin/env zsh

uuid=$(uuidgen)

echo "UUID: $uuid"
echo "UUID Base64: $(echo $uuid | xxd -r -p | base64)"
