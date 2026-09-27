//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Limits imposed on attachments we receive from others.
public struct IncomingAttachmentLimits {
    private let remoteConfig: RemoteConfig

    public static func currentLimits(remoteConfig: RemoteConfig) -> Self {
        return Self(remoteConfig: remoteConfig)
    }

    public static func addingFudgeFactor(toByteCount byteCount: UInt64) -> UInt64? {
        let fudgeFactor = byteCount / 4
        let result = byteCount.addingReportingOverflow(fudgeFactor)
        if result.overflow {
            return nil
        }
        return result.partialValue
    }

    init(remoteConfig: RemoteConfig) {
        self.remoteConfig = remoteConfig
    }

    public var maxEncryptedBytes: UInt64 {
        return remoteConfig.attachmentMaxEncryptedReceiveBytes
    }

    public var maxEncryptedImageBytes: UInt64 {
        // TODO: Compute this based on the outgoing limit.
        return 100 * 1024 * 1024
    }
}

// MARK: -

/// Limits imposed on attachments we send to others.
public struct OutgoingAttachmentLimits {
    private let remoteConfig: RemoteConfig
    private let callingCode: PhoneNumberUtil.LocalCallingCode?

    public static func currentLimits(
        remoteConfig: RemoteConfig = .current,
        callingCode: PhoneNumberUtil.LocalCallingCode? = Self.currentLocalCallingCode(),
    ) -> Self {
        return Self(remoteConfig: remoteConfig, callingCode: callingCode)
    }

    public static func currentLocalCallingCode() -> PhoneNumberUtil.LocalCallingCode? {
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        guard let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            return nil
        }
        return phoneNumberUtil.localCallingCode(localIdentifiers: localIdentifiers)
    }

    init(
        remoteConfig: RemoteConfig,
        callingCode: PhoneNumberUtil.LocalCallingCode?,
    ) {
        self.remoteConfig = remoteConfig
        self.callingCode = callingCode
    }

    // MARK: - Overall

    public var maxPlaintextBytes: UInt64 {
        let maxEncryptedBytes = remoteConfig.attachmentMaxEncryptedBytes
        return PaddingBucket.forEncryptedSizeLimit(maxEncryptedBytes).plaintextSize
    }

    public var maxPlaintextVideoBytes: UInt64 {
        let maxEncryptedBytes = remoteConfig.videoAttachmentMaxEncryptedBytes
        return PaddingBucket.forEncryptedSizeLimit(maxEncryptedBytes).plaintextSize
    }

    public var maxPlaintextAudioBytes: UInt64 {
        return maxPlaintextBytes
    }

    public var standardQualityLevel: ImageQualityLevel {
        return ImageQualityLevel.standardQualityLevel(
            remoteConfig: remoteConfig,
            callingCode: callingCode,
        )
    }
}

// MARK: -

struct ValidatedMessageBodyAttachmentProtos: CustomStringConvertible {
    let wrapped: [SSKProtoAttachmentPointer]

    fileprivate var oversizeText: [SSKProtoAttachmentPointer] = []
    fileprivate var visualMedia: [SSKProtoAttachmentPointer] = []
    fileprivate var nonVisualMedia: [SSKProtoAttachmentPointer] = []

    init(wrapped: [SSKProtoAttachmentPointer]) {
        self.wrapped = wrapped
    }

    var isEmpty: Bool { wrapped.isEmpty }

    var description: String {
        "oversizeText \(oversizeText.count); visualMedia \(visualMedia.count); nonVisualMedia \(nonVisualMedia.count)"
    }
}

public struct MessageBodyAttachmentLimits {
    /// How many visual-media attachments are allowed in a message body.
    public static let maxAllowedVisualMedia: Int = 32

    /// One more than ``maxAllowedVisualMedia``, to allow for long-text.
    public static let maxAllowedOverall: Int = maxAllowedVisualMedia + 1

    public init() {}

    func validateMessageBodyProtos(
        _ messageBodyProtos: [SSKProtoAttachmentPointer],
    ) throws -> ValidatedMessageBodyAttachmentProtos {
        guard messageBodyProtos.count <= Self.maxAllowedOverall else {
            throw OWSGenericError("too many body attachments overall!")
        }

        var validated = ValidatedMessageBodyAttachmentProtos(wrapped: messageBodyProtos)
        for proto in validated.wrapped {
            if proto.isOversizeText {
                validated.oversizeText.append(proto)
            } else if proto.isVisualMedia {
                validated.visualMedia.append(proto)
            } else {
                validated.nonVisualMedia.append(proto)
            }
        }

        if validated.oversizeText.count > 1 {
            throw OWSGenericError("too many oversize text protos! \(validated)")
        }
        if validated.visualMedia.count > Self.maxAllowedVisualMedia {
            throw OWSGenericError("too many visual-media protos! \(validated)")
        }
        if validated.nonVisualMedia.count > 1 {
            throw OWSGenericError("too many non-visual-media protos! \(validated)")
        }
        if !(validated.visualMedia.isEmpty || validated.nonVisualMedia.isEmpty) {
            throw OWSGenericError("both visual and non-visual media protos present! \(validated)")
        }
        return validated
    }
}
