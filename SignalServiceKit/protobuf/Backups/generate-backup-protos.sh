#!/usr/bin/env bash

REPO_ROOT=$(git rev-parse --show-toplevel)
BACKUP_PROTO_DIR="$REPO_ROOT/SignalServiceKit/protobuf/Backups"
BACKUP_PROTO_FILE="$BACKUP_PROTO_DIR/Backup.proto"
BACKUP_SWIFT_FILE="$BACKUP_PROTO_DIR/Backup.pb.swift"

echo "Generating Backup.pb.swift file with protoc and Swift-Protobuf..."

protoc \
  --proto_path="$BACKUP_PROTO_DIR" \
  --swift_out="$BACKUP_PROTO_DIR" \
  --swift_opt=Visibility=public \
  --swift_opt=UseAccessLevelOnImports=true \
  "$BACKUP_PROTO_FILE"

"$REPO_ROOT"/Scripts/lint/lint-license-headers --fix "$BACKUP_PROTO_FILE"
