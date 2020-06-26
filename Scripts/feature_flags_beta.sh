#!/bin/bash

sed -i'.backup' 's/^let build: FeatureBuild.*$/let build: FeatureBuild = OWSIsDebugBuild() ? .dev : .beta/g' SignalServiceKit/src/Util/FeatureFlags.swift
rm SignalServiceKit/src/Util/FeatureFlags.swift.backup
git add .
git commit -m "Feature flags for .beta."