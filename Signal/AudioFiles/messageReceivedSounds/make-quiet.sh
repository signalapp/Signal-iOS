#!/bin/bash

ffmpeg -i aurora.aifc -filter:a "volume=0.5" aurora-quiet.aifc
ffmpeg -i bamboo.aifc -filter:a "volume=0.5" bamboo-quiet.aifc
ffmpeg -i chord.aifc -filter:a "volume=0.5" chord-quiet.aifc
ffmpeg -i circles.aifc -filter:a "volume=0.5" circles-quiet.aifc
ffmpeg -i classic.aifc -filter:a "volume=0.5" classic-quiet.aifc
ffmpeg -i complete.aifc -filter:a "volume=0.5" complete-quiet.aifc
ffmpeg -i hello.aifc -filter:a "volume=0.5" hello-quiet.aifc
ffmpeg -i input.aifc -filter:a "volume=0.5" input-quiet.aifc
ffmpeg -i keys.aifc -filter:a "volume=0.5" keys-quiet.aifc
ffmpeg -i note.aifc -filter:a "volume=0.5" note-quiet.aifc
ffmpeg -i popcorn.aifc -filter:a "volume=0.5" popcorn-quiet.aifc
ffmpeg -i pulse.aifc -filter:a "volume=0.5" pulse-quiet.aifc
ffmpeg -i synth.aifc -filter:a "volume=0.5" synth-quiet.aifc
