//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import SignalServiceKit

final class CallingAssetsFetcher {

    private let logger: PrefixedLogger
    private let signalService: OWSSignalServiceProtocol

    init(
        signalService: OWSSignalServiceProtocol,
    ) {
        self.logger = PrefixedLogger(prefix: "[CallingAssets]")
        self.signalService = signalService
    }

    // MARK: -

    func fetchLocalAssets(ignore: Set<CallingAssetManifestEntry>) -> [(CallingAssetManifestEntry, Data)] {
        return CALLING_ASSET_MANIFEST.compactMap { manifestEntry in
            if ignore.contains(manifestEntry) {
                return nil
            }

            if let data = fetchFileAsset(entry: manifestEntry) {
                return (manifestEntry, data)
            }

            return nil
        }
    }

    func cleanupStaleAssets() throws {
        let baseUrl = assetsDirectory
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: baseUrl.path)
        } catch {
            owsFailDebug("Failed to read contents of calling assets directory! \(error)", logger: logger)
            throw error
        }

        for fileName in files {
            let fileUrl = baseUrl.appendingPathComponent(fileName)

            guard FileManager.default.isDeletableFile(atPath: fileUrl.path) else {
                continue
            }

            if CALLING_ASSET_MANIFEST_MAP[fileName] == nil {
                do {
                    try FileManager.default.removeItem(at: fileUrl)
                    logger.info("Deleted stale calling asset file: \(fileUrl.path)")
                } catch {
                    owsFailDebug("Failed to delete stale calling asset! \(error)", logger: logger)
                    throw error
                }
            }
        }
    }

    // MARK: -

    func fetchMissingRemoteAssets() async -> [Result<Void, Error>] {
        return await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for entry in CALLING_ASSET_MANIFEST {
                if hasFileAsset(entry: entry) {
                    continue
                }

                taskGroup.addTask { [self] in
                    do {
                        try await fetchRemoteAsset(entry: entry)
                        logger.info("Fetched remote calling asset: \(entry.name)")
                    } catch let error {
                        logger.warn("Failed to fetch calling asset: \(entry.name)! \(error)")
                        throw error
                    }
                }
            }

            var results: [Result<Void, Error>] = []
            while let result = await taskGroup.nextResult() {
                results.append(result)
            }
            return results
        }
    }

    private func fetchRemoteAsset(entry: CallingAssetManifestEntry) async throws {
        logger.info("Fetching remote asset: \(entry.name)")

        let response = try await signalService.urlSessionForUpdates2().performDownload(
            entry.path,
            method: .get,
        )

        guard let content = FileManager.default.contents(atPath: response.downloadUrl.path) else {
            throw OWSAssertionError("Missing downloaded calling asset file: \(entry.name)", logger: logger)
        }

        guard
            content.count == entry.size,
            SHA512.hash(data: content) == entry.digest
        else {
            throw OWSAssertionError("Downloaded calling asset file has unexpected size/hash: \(entry.name)", logger: logger)
        }

        guard let assetFileUrl = assetFileUrl(forAssetEntry: entry) else {
            throw OWSAssertionError("Missing asset file URL for entry: \(entry.name)", logger: logger)
        }

        do {
            try FileManager.default.moveItem(
                at: response.downloadUrl,
                to: assetFileUrl,
            )
        } catch let error {
            throw OWSAssertionError("Failed to move downloaded calling asset! \(error)", logger: logger)
        }
    }

    // MARK: - Filesystem Interaction

    private let assetsDirectory: URL = {
        let assetsSubdirectory: String = "CallingAssets"
        return OWSFileSystem.appSharedDataDirectoryURL().appendingPathComponent(assetsSubdirectory)
    }()

    private func assetFileUrl(forAssetEntry entry: CallingAssetManifestEntry) -> URL? {
        guard OWSFileSystem.ensureDirectoryExists(assetsDirectory.path) else {
            return nil
        }

        return assetsDirectory.appendingPathComponent(entry.name)
    }

    private func hasFileAsset(entry: CallingAssetManifestEntry) -> Bool {
        guard let url = assetFileUrl(forAssetEntry: entry) else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private func fetchFileAsset(entry: CallingAssetManifestEntry) -> Data? {
        guard let url = assetFileUrl(forAssetEntry: entry) else {
            return nil
        }

        return FileManager.default.contents(atPath: url.path)
    }
}

// MARK: - Asset Manifest

struct CallingAssetManifestEntry: Hashable {
    let assetGroup: String
    let name: String
    let digest: Data
    let path: String
    let size: UInt64
}

private let CALLING_ASSET_MANIFEST: Array<CallingAssetManifestEntry> = [
    CallingAssetManifestEntry(
        assetGroup: "opus-dred",
        name: "calling-dred_weights-1_6_1-f4aed08a.bin",
        digest: Data(base64Encoded: "sdfpdb/u3wiTfBr2s0gx1LJX6jii4tquyax/UBThTGWTEXyOCSKjYmYV+9tKQZcO+Q1B1ReoGSW3VbvzeMGKaQ==")!,
        path: "static/android/calling/deep_plc-dred_weights-1_6_1-f4aed08a.bin",
        size: 1998208,
    ),
]

private let CALLING_ASSET_MANIFEST_MAP: [String: CallingAssetManifestEntry] = Dictionary(
    uniqueKeysWithValues: CALLING_ASSET_MANIFEST.map { ($0.name, $0) },
)
