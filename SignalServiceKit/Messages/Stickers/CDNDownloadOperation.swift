//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum CDNDownloadOperation {

    // MARK: - Dependencies

    private static func buildUrlSession(maxResponseSize: UInt) -> OWSURLSessionProtocol {
        SSKEnvironment.shared.signalServiceRef.urlSessionForCdn(cdnNumber: 0, maxResponseSize: maxResponseSize)
    }

    // MARK: -

    static let kMaxStickerDataDownloadSize: UInt = 1000 * 1000
    static let kMaxStickerPackDownloadSize: UInt = 1000 * 1000

    public static func tryToDownload(urlPath: String, maxDownloadSize: UInt) async throws -> URL {
        guard !isCorrupt(urlPath: urlPath) else {
            Logger.warn("Skipping download of corrupt data.")
            throw StickerError.corruptData
        }

        do {
            let urlSession = self.buildUrlSession(maxResponseSize: maxDownloadSize)
            let headers = ["Content-Type": MimeType.applicationOctetStream.rawValue]
            let response = try await urlSession.performDownload(urlPath, method: .get, headers: headers)

            let downloadUrl = response.downloadUrl
            do {
                let temporaryFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
                try OWSFileSystem.moveFile(from: downloadUrl, to: temporaryFileUrl)
                return temporaryFileUrl
            } catch {
                owsFailDebug("Could not move to temporary file: \(error)")
                // Fail immediately; do not retry.
                throw SSKUnretryableError.downloadCouldNotMoveFile
            }
        } catch {
            Logger.warn("Download failed: \(error)")
            throw error
        }
    }

    public static func tryToDownload(urlPath: String, maxDownloadSize: UInt) async throws -> Data {
        let downloadUrl: URL = try await tryToDownload(urlPath: urlPath, maxDownloadSize: maxDownloadSize)
        do {
            let data = try Data(contentsOf: downloadUrl)
            try OWSFileSystem.deleteFile(url: downloadUrl)
            return data
        } catch {
            owsFailDebug("Could not load data failed: \(error)")
            // Fail immediately; do not retry.
            throw SSKUnretryableError.downloadCouldNotDeleteFile
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
