//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Message Backup

extension OWSRequestFactory {
    public static func reserveBackupId(
        backupId: String,
        auth: ChatServiceAuth = .implicit()
    ) throws -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/backupid")!,
            method: "PUT",
            parameters: ["backupAuthCredentialRequest": backupId]
        )
        request.setAuth(auth)
        return request
    }

    public static func backupAuthenticationCredentialRequest(
        from fromRedemptionSeconds: UInt64,
        to toRedemptionSeconds: UInt64,
        auth: ChatServiceAuth
    ) -> TSRequest {
        owsAssertDebug(fromRedemptionSeconds > 0)
        owsAssertDebug(toRedemptionSeconds > 0)
        let request = TSRequest(url: URL(string: "v1/archives/auth?redemptionStartSeconds=\(fromRedemptionSeconds)&redemptionEndSeconds=\(toRedemptionSeconds)")!, method: "GET", parameters: nil)
        request.setAuth(auth)
        return request
    }

    public static func backupSetPublicKeyRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/keys")!,
            method: "PUT",
            parameters: ["backupIdPublicKey": Data(auth.publicKey.serialize()).base64EncodedString()]
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func backupUploadFormRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/upload/form")!,
            method: "GET",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func backupMediaUploadFormRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/media/upload/form")!,
            method: "GET",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func backupInfoRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "GET",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func backupRefreshInfoRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "PUT",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func deleteBackupRequest(auth: MessageBackupServiceAuth) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "DELETE",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func fetchCDNCredentials(auth: MessageBackupServiceAuth, cdn: Int32) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/auth/read?cdn=\(cdn)")!,
            method: "GET",
            parameters: nil
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func copyToMediaTier(
        auth: MessageBackupServiceAuth,
        transitCdnNumber: UInt32,
        transitCdnKey: String,
        objectLength: UInt32,
        mediaId: Data,
        hmacKey: Data,
        encryptionKey: Data,
        iv: Data
    ) -> TSRequest {
        let parameters: [String: Any] = [
            "sourceAttachment": [
                "cdn": transitCdnNumber,
                "key": transitCdnKey
            ],
            "objectLength": objectLength,
            "mediaId": mediaId.asBase64Url,
            "hmacKey": hmacKey.base64EncodedString(),
            "encryptionKey": encryptionKey.base64EncodedString(),
            "iv": iv.base64EncodedString()
        ]
        let request = TSRequest(
            url: URL(string: "v1/archives/media")!,
            method: "PUT",
            parameters: parameters
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }
}
