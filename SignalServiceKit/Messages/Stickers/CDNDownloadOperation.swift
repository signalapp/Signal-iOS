//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum CDNDownloadOperation {

    // MARK: - Dependencies

    private static func buildUrlSession() async -> OWSURLSessionProtocol {
        await SSKEnvironment.shared.signalServiceRef.sharedUrlSessionForCdn(cdnNumber: 0)
    }

    // MARK: -

    static let kMaxStickerDataDownloadSize: UInt64 = 1000 * 1000
    static let kMaxStickerPackDownloadSize: UInt64 = 1000 * 1000

    static func tryToDownload(urlPath: String, maxDownloadSize: UInt64) async throws -> URL {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }

        do {
            let urlSession = await self.buildUrlSession()
            let headers: HttpHeaders = ["Content-Type": MimeType.applicationOctetStream.rawValue]
            let response = try await urlSession.performDownload(urlPath, method: .get, headers: headers, maxResponseSize: maxDownloadSize)

            let downloadUrl = response.downloadUrl
            do {
                let temporaryFileUrl = OWSFileSystem.temporaryFileUrl(
                    fileExtension: nil,
                    isAvailableWhileDeviceLocked: true,
                )
                try OWSFileSystem.moveFile(from: downloadUrl, to: temporaryFileUrl)
                return temporaryFileUrl
            } catch {
                // Fail immediately; do not retry.
                throw OWSAssertionError("Could not move to temporary file: \(error)")
            }
        } catch {
            Logger.warn("Download failed: \(error)")
            throw error
        }
    }

    static func tryToDownload(urlPath: String, maxDownloadSize: UInt64) async throws -> Data {
        let downloadUrl: URL = try await tryToDownload(urlPath: urlPath, maxDownloadSize: maxDownloadSize)
        do {
            let data = try Data(contentsOf: downloadUrl)
            try OWSFileSystem.deleteFile(url: downloadUrl)
            return data
        } catch {
            // Fail immediately; do not retry.
            throw OWSAssertionError("Could not load data failed: \(error)")
        }
    }

    // MARK: - Corrupt Data

    // We track corrupt downloads, to avoid retrying them more than once per launch.
    private static let corruptDataKeys = AtomicValue<Set<String>>(Set(), lock: .init())

    static func markUrlPathAsCorrupt(_ urlPath: String) {
        corruptDataKeys.update { _ = $0.insert(urlPath) }
    }

    static func isCorrupt(urlPath: String) -> Bool {
        return corruptDataKeys.update { $0.contains(urlPath) }
    }
}
