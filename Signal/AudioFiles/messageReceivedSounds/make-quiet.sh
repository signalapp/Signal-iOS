#!/bin/bash

ffmpeg -i aurora.m4r -filter:a "volume=0.5" aurora-quiet.caf
ffmpeg -i bamboo.m4r -filter:a "volume=0.5" bamboo-quiet.caf
ffmpeg -i chord.m4r -filter:a "volume=0.5" chord-quiet.caf
ffmpeg -i circles.m4r -filter:a "volume=0.5" circles-quiet.caf
ffmpeg -i complete.m4r -filter:a "volume=0.5" complete-quiet.caf
ffmpeg -i hello.m4r -filter:a "volume=0.5" hello-quiet.caf
ffmpeg -i input.m4r -filter:a "volume=0.5" input-quiet.caf
ffmpeg -i keys.m4r -filter:a "volume=0.5" keys-quiet.caf
ffmpeg -i note.m4r -filter:a "volume=0.5" note-quiet.caf
ffmpeg -i popcorn.m4r -filter:a "volume=0.5" popcorn-quiet.caf
ffmpeg -i pulse.m4r -filter:a "volume=0.5" pulse-quiet.caf
ffmpeg -i synth.m4r -filter:a "volume=0.5" synth-quiet.caf
