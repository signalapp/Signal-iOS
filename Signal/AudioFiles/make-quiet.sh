#!/bin/bash

ffmpeg -i "messageReceivedClassic.aifc" -filter:a "volume=0.5" "messageReceivedClassic-quiet.caf"
