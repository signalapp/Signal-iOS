# SignalServiceKit Protobufs

These protobuf definitions are copied from Signal-Android, but modified
to include a conventional ObjC classnames.

e.g.

    import "objectivec-descriptor.proto";
    option (google.protobuf.objectivec_file_options).class_prefix = "OWSFingerprintProtos";

## Prequisites

Install protobuf 2.6, the objc plugin doesn't currently work with
protobuf 3.0

    brew install protobuf@2.6
    # Beware if you are depending on protobuf 3.0 elsewhere
    brew link --force protobuf@2.6

Install the objc plugin to $SignalServiceKitRoot/..

e.g. I have SignalServiceKit installed to ~/src/WhisperSystems/SignalServiceKit

So I run

    cd ~/src/WhisperSystems
    git clone https://github.com/alexeyxo/protobuf-objc

Follow the install instructions at https://github.com/alexeyxo/protobuf-objc

## Building Protobuf

After changes are made to any proto, generate the ObjC classes by
running:

    cd ~/src/WhisperSystems/SignalServiceKit/protobuf
    make

