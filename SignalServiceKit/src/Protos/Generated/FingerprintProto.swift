//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum FingerprintProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - FingerprintProtoLogicalFingerprint

@objc public class FingerprintProtoLogicalFingerprint: NSObject {

    // MARK: - FingerprintProtoLogicalFingerprintBuilder

    @objc public class FingerprintProtoLogicalFingerprintBuilder: NSObject {

        private var proto = FingerprintProtos_LogicalFingerprint()

        @objc public override init() {}

        @objc public func setIdentityData(_ valueParam: Data) {
            proto.identityData = valueParam
        }

        @objc public func build() throws -> FingerprintProtoLogicalFingerprint {
            let wrapper = try FingerprintProtoLogicalFingerprint.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: FingerprintProtos_LogicalFingerprint

    @objc public var identityData: Data? {
        guard proto.hasIdentityData else {
            return nil
        }
        return proto.identityData
    }
    @objc public var hasIdentityData: Bool {
        return proto.hasIdentityData
    }

    private init(proto: FingerprintProtos_LogicalFingerprint) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprint -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprint -

        let result = FingerprintProtoLogicalFingerprint(proto: proto)
        return result
    }
}

// MARK: - FingerprintProtoLogicalFingerprints

@objc public class FingerprintProtoLogicalFingerprints: NSObject {

    // MARK: - FingerprintProtoLogicalFingerprintsBuilder

    @objc public class FingerprintProtoLogicalFingerprintsBuilder: NSObject {

        private var proto = FingerprintProtos_LogicalFingerprints()

        @objc public override init() {}

        @objc public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        @objc public func setLocalFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
            proto.localFingerprint = valueParam.proto
        }

        @objc public func setRemoteFingerprint(_ valueParam: FingerprintProtoLogicalFingerprint) {
            proto.remoteFingerprint = valueParam.proto
        }

        @objc public func build() throws -> FingerprintProtoLogicalFingerprints {
            let wrapper = try FingerprintProtoLogicalFingerprints.parseProto(proto)
            return wrapper
        }
    }

    fileprivate let proto: FingerprintProtos_LogicalFingerprints

    @objc public let localFingerprint: FingerprintProtoLogicalFingerprint?
    @objc public let remoteFingerprint: FingerprintProtoLogicalFingerprint?

    @objc public var version: UInt32 {
        return proto.version
    }
    @objc public var hasVersion: Bool {
        return proto.hasVersion
    }

    private init(proto: FingerprintProtos_LogicalFingerprints,
                 localFingerprint: FingerprintProtoLogicalFingerprint?,
                 remoteFingerprint: FingerprintProtoLogicalFingerprint?) {
        self.proto = proto
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
        var localFingerprint: FingerprintProtoLogicalFingerprint? = nil
        if proto.hasLocalFingerprint {
            localFingerprint = try FingerprintProtoLogicalFingerprint.parseProto(proto.localFingerprint)
        }

        var remoteFingerprint: FingerprintProtoLogicalFingerprint? = nil
        if proto.hasRemoteFingerprint {
            remoteFingerprint = try FingerprintProtoLogicalFingerprint.parseProto(proto.remoteFingerprint)
        }

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprints -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprints -

        let result = FingerprintProtoLogicalFingerprints(proto: proto,
                                                         localFingerprint: localFingerprint,
                                                         remoteFingerprint: remoteFingerprint)
        return result
    }
}
