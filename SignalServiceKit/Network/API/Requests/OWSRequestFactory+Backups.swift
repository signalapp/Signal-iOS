//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Message Backup

extension OWSRequestFactory {
    public static func backupAuthenticationCredentialRequest(
        from fromRedemptionSeconds: UInt64,
        to toRedemptionSeconds: UInt64,
        auth: ChatServiceAuth
    ) -> TSRequest {
        owsAssertDebug(fromRedemptionSeconds > 0)
        owsAssertDebug(toRedemptionSeconds > 0)
        var request = TSRequest(url: URL(string: "v1/archives/auth?redemptionStartSeconds=\(fromRedemptionSeconds)&redemptionEndSeconds=\(toRedemptionSeconds)")!, method: "GET", parameters: nil)
        request.auth = .identified(auth)
        return request
    }

    /// - parameter backupByteLength: length in bytes of the encrypted backup file we will upload
    public static func backupUploadFormRequest(
        backupByteLength: UInt32,
        auth: BackupServiceAuth
    ) -> TSRequest {
        var urlComps = URLComponents(string: "v1/archives/upload/form")!
        urlComps.queryItems = [URLQueryItem(name: "uploadLength", value: "\(backupByteLength)")]
        var request = TSRequest(
            url: urlComps.url!,
            method: "GET",
            parameters: nil
        )
        request.auth = .backup(auth)
        return request
    }

    public static func backupMediaUploadFormRequest(auth: BackupServiceAuth) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/media/upload/form")!,
            method: "GET",
            parameters: nil
        )
        request.auth = .backup(auth)
        return request
    }

    public static func backupInfoRequest(auth: BackupServiceAuth) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "GET",
            parameters: nil
        )
        request.auth = .backup(auth)
        return request
    }

    public static func backupRefreshInfoRequest(auth: BackupServiceAuth) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives")!,
            method: "PUT",
            parameters: nil
        )
        request.auth = .backup(auth)
        return request
    }

    public static func fetchBackupCDNCredentials(auth: BackupServiceAuth, cdn: Int32) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/auth/read?cdn=\(cdn)")!,
            method: "GET",
            parameters: nil
        )
        request.auth = .backup(auth)
        return request
    }

    public static func copyToMediaTier(
        auth: BackupServiceAuth,
        item: BackupArchive.Request.MediaItem
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/media")!,
            method: "PUT",
            parameters: item.asParameters
        )
        request.auth = .backup(auth)
        return request
    }

    public static func archiveMedia(
        auth: BackupServiceAuth,
        items: [BackupArchive.Request.MediaItem]
    ) -> TSRequest {
        let parameters: [String: Any] = [ "items": items.map(\.asParameters) ]
        var request = TSRequest(
            url: URL(string: "v1/archives/media/batch")!,
            method: "PUT",
            parameters: parameters
        )
        request.auth = .backup(auth)
        return request
    }

    public static func listMedia(
        auth: BackupServiceAuth,
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
        var request = TSRequest(
            url: urlComponents.url!,
            method: "GET",
            parameters: [:]
        )
        request.auth = .backup(auth)
        return request
    }

    public static func deleteMedia(
        auth: BackupServiceAuth,
        objects: [BackupArchive.Request.DeleteMediaTarget]
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/archives/media/delete")!,
            method: "POST",
            parameters: ["mediaToDelete": NSArray(array: objects.map(\.asParameters))]
        )
        request.auth = .backup(auth)
        return request
    }

    public static func redeemReceipt(
        receiptCredentialPresentation: Data
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/archives/redeem-receipt")!,
            method: "POST",
            parameters: ["receiptCredentialPresentation": receiptCredentialPresentation.base64EncodedString()]
        )
    }
}
