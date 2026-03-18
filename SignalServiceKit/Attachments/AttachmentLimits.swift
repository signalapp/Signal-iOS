//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Limits imposed on attachments we receive from others.
public struct IncomingAttachmentLimits {
    private let remoteConfig: RemoteConfig

    public static func currentLimits(remoteConfig: RemoteConfig = .current) -> Self {
        return Self(remoteConfig: remoteConfig)
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
    private let callingCode: Int?

    public static func currentLimits(
        remoteConfig: RemoteConfig = .current,
        callingCode: Int? = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction.flatMap({
            return SSKEnvironment.shared.phoneNumberUtilRef.localCallingCode(localIdentifiers: $0)
        }),
    ) -> Self {
        return Self(remoteConfig: remoteConfig, callingCode: callingCode)
    }

    init(
        remoteConfig: RemoteConfig,
        callingCode: Int?,
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
