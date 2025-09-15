# SignalServiceKit Protobufs

These protobuf definitions are the same as/compatible with Signal-Android and
Signal-Desktop, though modified slightly to match iOS conventions.

## Prerequisites

Install Apple's `swift-protobuf` (*not* the similarly named `protobuf-swift`)

    brew install swift-protobuf

This should install an up-to-date protobuf package as a dependency.

## Compiling Protos

    cd SignalServiceKit/Protos
    make

