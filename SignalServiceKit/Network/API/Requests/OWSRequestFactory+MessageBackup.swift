//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Message Backup

extension OWSRequestFactory {
    public static func reserveBackupId(
        backupId: String,
        mediaBackupId: String,
        auth: ChatServiceAuth = .implicit()
    ) throws -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/backupid")!,
            method: "PUT",
            parameters: [
                "messagesBackupAuthCredentialRequest": backupId,
                "mediaBackupAuthCredentialRequest": mediaBackupId
            ]
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
        item: MessageBackup.Request.MediaItem
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/media")!,
            method: "PUT",
            parameters: item.asParameters
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func archiveMedia(
        auth: MessageBackupServiceAuth,
        items: [MessageBackup.Request.MediaItem]
    ) -> TSRequest {
        let parameters: [String: Any] = [ "items": items.map(\.asParameters) ]
        let request = TSRequest(
            url: URL(string: "v1/archives/media/batch")!,
            method: "PUT",
            parameters: parameters
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func listMedia(
        auth: MessageBackupServiceAuth,
        cursor: String?,
        limit: UInt32?
    ) -> TSRequest {
        var urlComponents = URLComponents(string: "v1/archives/media")!
        var queryItems = [URLQueryItem]()
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        let request = TSRequest(
            url: urlComponents.url!,
            method: "GET",
            parameters: [:]
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func deleteMedia(
        auth: MessageBackupServiceAuth,
        objects: [MessageBackup.Request.DeleteMediaTarget]
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/media/delete")!,
            method: "POST",
            parameters: ["mediaToDelete": NSArray(array: objects.map(\.asParameters))]
        )
        auth.apply(to: request)
        request.shouldHaveAuthorizationHeaders = false
        return request
    }

    public static func redeemReceipt(
        receiptCredentialPresentation: Data
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/archives/redeem-receipt")!,
            method: "POST",
            parameters: ["receiptCredentialPresentation": receiptCredentialPresentation.base64EncodedString()]
        )
        request.shouldHaveAuthorizationHeaders = false
        return request
    }
}
