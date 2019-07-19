//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum FingerprintProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - FingerprintProtoLogicalFingerprint

@objc public class FingerprintProtoLogicalFingerprint: NSObject {

    // MARK: - FingerprintProtoLogicalFingerprintBuilder

    @objc public class func builder(identityData: Data) -> FingerprintProtoLogicalFingerprintBuilder {
        return FingerprintProtoLogicalFingerprintBuilder(identityData: identityData)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> FingerprintProtoLogicalFingerprintBuilder {
        let builder = FingerprintProtoLogicalFingerprintBuilder(identityData: identityData)
        return builder
    }

    @objc public class FingerprintProtoLogicalFingerprintBuilder: NSObject {

        private var proto = FingerprintProtos_LogicalFingerprint()

        @objc fileprivate override init() {}

        @objc fileprivate init(identityData: Data) {
            super.init()

            setIdentityData(identityData)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setIdentityData(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.identityData = valueParam
        }

        public func setIdentityData(_ valueParam: Data) {
            proto.identityData = valueParam
        }

        @objc public func build() throws -> FingerprintProtoLogicalFingerprint {
            return try FingerprintProtoLogicalFingerprint.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try FingerprintProtoLogicalFingerprint.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: FingerprintProtos_LogicalFingerprint

    @objc public let identityData: Data

    private init(proto: FingerprintProtos_LogicalFingerprint,
                 identityData: Data) {
        self.proto = proto
        self.identityData = identityData
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> FingerprintProtoLogicalFingerprint {
        let proto = try FingerprintProtos_LogicalFingerprint(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: FingerprintProtos_LogicalFingerprint) throws -> FingerprintProtoLogicalFingerprint {
        guard proto.hasIdentityData else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(logTag) missing required field: identityData")
        }
        let identityData = proto.identityData

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprint -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprint -

        let result = FingerprintProtoLogicalFingerprint(proto: proto,
                                                        identityData: identityData)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension FingerprintProtoLogicalFingerprint {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension FingerprintProtoLogicalFingerprint.FingerprintProtoLogicalFingerprintBuilder {
    @objc public func buildIgnoringErrors() -> FingerprintProtoLogicalFingerprint? {
        return try! self.build()
    }
}

#endif

// MARK: - FingerprintProtoLogicalFingerprints

@objc public class FingerprintProtoLogicalFingerprints: NSObject {

    // MARK: - FingerprintProtoLogicalFingerprintsBuilder

    @objc public class func builder(version: UInt32, localFingerprint: FingerprintProtoLogicalFingerprint, remoteFingerprint: FingerprintProtoLogicalFingerprint) -> FingerprintProtoLogicalFingerprintsBuilder {
        return FingerprintProtoLogicalFingerprintsBuilder(version: version, localFingerprint: localFingerprint, remoteFingerprint: remoteFingerprint)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> FingerprintProtoLogicalFingerprintsBuilder {
        let builder = FingerprintProtoLogicalFingerprintsBuilder(version: version, localFingerprint: localFingerprint, remoteFingerprint: remoteFingerprint)
        return builder
    }

    @objc public class FingerprintProtoLogicalFingerprintsBuilder: NSObject {

        private var proto = FingerprintProtos_LogicalFingerprints()

        @objc fileprivate override init() {}

        @objc fileprivate init(version: UInt32, localFingerprint: FingerprintProtoLogicalFingerprint, remoteFingerprint: FingerprintProtoLogicalFingerprint) {
            super.init()

            setVersion(version)
            setLocalFingerprint(localFingerprint)
            setRemoteFingerprint(remoteFingerprint)
        }

        @objc
        public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setLocalFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint?) {
            guard let valueParam = valueParam else { return }
            proto.localFingerprint = valueParam.proto
        }

        public func setLocalFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
            proto.localFingerprint = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setRemoteFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint?) {
            guard let valueParam = valueParam else { return }
            proto.remoteFingerprint = valueParam.proto
        }

        public func setRemoteFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
            proto.remoteFingerprint = valueParam.proto
        }

        @objc public func build() throws -> FingerprintProtoLogicalFingerprints {
            return try FingerprintProtoLogicalFingerprints.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try FingerprintProtoLogicalFingerprints.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: FingerprintProtos_LogicalFingerprints

    @objc public let version: UInt32

    @objc public let localFingerprint: FingerprintProtoLogicalFingerprint

    @objc public let remoteFingerprint: FingerprintProtoLogicalFingerprint

    private init(proto: FingerprintProtos_LogicalFingerprints,
                 version: UInt32,
                 localFingerprint: FingerprintProtoLogicalFingerprint,
                 remoteFingerprint: FingerprintProtoLogicalFingerprint) {
        self.proto = proto
        self.version = version
        self.localFingerprint = localFingerprint
        self.remoteFingerprint = remoteFingerprint
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> FingerprintProtoLogicalFingerprints {
        let proto = try FingerprintProtos_LogicalFingerprints(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: FingerprintProtos_LogicalFingerprints) throws -> FingerprintProtoLogicalFingerprints {
        guard proto.hasVersion else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(logTag) missing required field: version")
        }
        let version = proto.version

        guard proto.hasLocalFingerprint else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(logTag) missing required field: localFingerprint")
        }
        let localFingerprint = try FingerprintProtoLogicalFingerprint.parseProto(proto.localFingerprint)

        guard proto.hasRemoteFingerprint else {
            throw FingerprintProtoError.invalidProtobuf(description: "\(logTag) missing required field: remoteFingerprint")
        }
        let remoteFingerprint = try FingerprintProtoLogicalFingerprint.parseProto(proto.remoteFingerprint)

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprints -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprints -

        let result = FingerprintProtoLogicalFingerprints(proto: proto,
                                                         version: version,
                                                         localFingerprint: localFingerprint,
                                                         remoteFingerprint: remoteFingerprint)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension FingerprintProtoLogicalFingerprints {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension FingerprintProtoLogicalFingerprints.FingerprintProtoLogicalFingerprintsBuilder {
    @objc public func buildIgnoringErrors() -> FingerprintProtoLogicalFingerprints? {
        return try! self.build()
    }
}

#endif
