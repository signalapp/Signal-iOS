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

    @objc public let identityData: Data?

    @objc public init(identityData: Data?) {
        self.identityData = identityData
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> FingerprintProtoLogicalFingerprint {
        let proto = try FingerprintProtos_LogicalFingerprint(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: FingerprintProtos_LogicalFingerprint) throws -> FingerprintProtoLogicalFingerprint {
        var identityData: Data? = nil
        if proto.hasIdentityData {
            identityData = proto.identityData
        }

        // MARK: - Begin Validation Logic for FingerprintProtoLogicalFingerprint -

        // MARK: - End Validation Logic for FingerprintProtoLogicalFingerprint -

        let result = FingerprintProtoLogicalFingerprint(identityData: identityData)
        return result
    }

    fileprivate var asProtobuf: FingerprintProtos_LogicalFingerprint {
        let proto = FingerprintProtos_LogicalFingerprint.with { (builder) in
            if let identityData = self.identityData {
                builder.identityData = identityData
            }
        }

        return proto
    }
}

// MARK: - FingerprintProtoLogicalFingerprints

@objc public class FingerprintProtoLogicalFingerprints: NSObject {

    @objc public let version: UInt32
    @objc public let localFingerprint: FingerprintProtoLogicalFingerprint?
    @objc public let remoteFingerprint: FingerprintProtoLogicalFingerprint?

    @objc public init(version: UInt32,
                      localFingerprint: FingerprintProtoLogicalFingerprint?,
                      remoteFingerprint: FingerprintProtoLogicalFingerprint?) {
        self.version = version
        self.localFingerprint = localFingerprint
        self.remoteFingerprint = remoteFingerprint
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.asProtobuf.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> FingerprintProtoLogicalFingerprints {
        let proto = try FingerprintProtos_LogicalFingerprints(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: FingerprintProtos_LogicalFingerprints) throws -> FingerprintProtoLogicalFingerprints {
        var version: UInt32 = 0
        if proto.hasVersion {
            version = proto.version
        }

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

        let result = FingerprintProtoLogicalFingerprints(version: version,
                                                         localFingerprint: localFingerprint,
                                                         remoteFingerprint: remoteFingerprint)
        return result
    }

    fileprivate var asProtobuf: FingerprintProtos_LogicalFingerprints {
        let proto = FingerprintProtos_LogicalFingerprints.with { (builder) in
            builder.version = self.version

            if let localFingerprint = self.localFingerprint {
                builder.localFingerprint = localFingerprint.asProtobuf
            }

            if let remoteFingerprint = self.remoteFingerprint {
                builder.remoteFingerprint = remoteFingerprint.asProtobuf
            }
        }

        return proto
    }
}
