#!/bin/sh

set -eux

# We generate Swift extensions to handle serialization, etc. for models.
RECORD_TYPE_SWIFT="SignalServiceKit/Storage/Database/SDSRecordType.swift"
RECORD_TYPE_JSON="Scripts/sds_codegen/sds_config/sds_record_type_map.json"
CONFIG_JSON="Scripts/sds_codegen/sds_config/sds-config.json"
PROPERTY_ORDER_JSON="Scripts/sds_codegen/sds_config/sds-property_order.json"
GENERATE_ARGS="--record-type-swift-path $RECORD_TYPE_SWIFT  --record-type-json-path $RECORD_TYPE_JSON --config-json-path $CONFIG_JSON --property-order-json-path $PROPERTY_ORDER_JSON"
Scripts/sds_codegen/sds_generate.py  --src-path SignalServiceKit/  --search-path .  $GENERATE_ARGS
