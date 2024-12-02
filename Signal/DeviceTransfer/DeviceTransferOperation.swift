//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit

// Use the main thread for all MCSession related operations.
// There shouldn't be anything else going on in the app, anyway.
@MainActor
class DeviceTransferOperation: NSObject {
    let file: DeviceTransferProtoFile

    init(file: DeviceTransferProtoFile) {
        self.file = file
    }

    // MARK: - Run

    func run() async throws {
        Logger.info("Transferring file: \(file.identifier), estimatedSize: \(file.estimatedSize)")
        try Task.checkCancellation()
        try await self.prepareForSending()
    }

    private func prepareForSending() async throws {
        guard case .outgoing(let newDevicePeerId, _, _, let transferredFiles, let progress) = AppEnvironment.shared.deviceTransferServiceRef.transferState else {
            throw OWSAssertionError("Tried to transfer file while in unexpected state: \(AppEnvironment.shared.deviceTransferServiceRef.transferState)")
        }

        if transferredFiles.contains(file.identifier) {
            Logger.info("File was already transferred, skipping")
            return
        }

        var url = URL(fileURLWithPath: file.relativePath, relativeTo: DeviceTransferService.appSharedDataDirectory)

        if !OWSFileSystem.fileOrFolderExists(url: url) {
            guard ![
                DeviceTransferService.databaseWALIdentifier,
                DeviceTransferService.databaseIdentifier
            ].contains(file.identifier) else {
                throw OWSAssertionError("Mandatory database file is missing for transfer")
            }

            Logger.warn("Missing file for transfer, it probably disappeared or was otherwise deleted. Sending missing file placeholder.")

            url = URL(
                fileURLWithPath: UUID().uuidString,
                relativeTo: URL(fileURLWithPath: OWSTemporaryDirectory(), isDirectory: true)
            )
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: DeviceTransferService.missingFileData,
                attributes: nil
            ) else {
                throw OWSAssertionError("Failed to create temp file for missing file \(url)")
            }
        }

        guard let sha256Digest = try? Cryptography.computeSHA256DigestOfFile(at: url) else {
            throw OWSAssertionError("Failed to calculate sha256 for file")
        }

        guard let session = AppEnvironment.shared.deviceTransferServiceRef.session else {
            throw OWSAssertionError("Tried to transfer file with no active session")
        }
        let fileProgress = AtomicValue<Progress?>(nil, lock: .init())
        defer {
            fileProgress.update { $0?.removeObserver(self, forKeyPath: "fractionCompleted") }
        }
        try await withCheckedThrowingContinuation { continuation in
            fileProgress.update {
                let _fileProgress = session.sendResource(
                    at: url,
                    withName: file.identifier + " " + sha256Digest.hexadecimalString,
                    toPeer: newDevicePeerId,
                    withCompletionHandler: { error in
                        continuation.resume(with: error.map({ .failure(OWSGenericError("Transferring file \(self.file.identifier) failed \($0)")) }) ?? .success(()))
                    }
                )
                if let _fileProgress {
                    progress.addChild(_fileProgress, withPendingUnitCount: Int64(file.estimatedSize))
                    _fileProgress.addObserver(self, forKeyPath: "fractionCompleted", options: .initial, context: nil)
                    $0 = _fileProgress
                }
            }
        }
        try Task.checkCancellation()

        Logger.info("Transferring file \(self.file.identifier) complete")
        AppEnvironment.shared.deviceTransferServiceRef.transferState = AppEnvironment.shared.deviceTransferServiceRef.transferState.appendingFileId(self.file.identifier)
    }

    private var lastWholeNumberProgress = 0
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "fractionCompleted", let progress = object as? Progress else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }

        let currentWholeNumberProgress = Int(progress.fractionCompleted * 100)
        let percentChange = currentWholeNumberProgress - lastWholeNumberProgress

        defer { lastWholeNumberProgress = currentWholeNumberProgress }

        // Determine how frequently to log progress updates. If in verbose mode, we log
        // every 1%. Otherwise, every 10%.
        guard percentChange >= (DebugFlags.deviceTransferVerboseProgressLogging ? 1 : 10) else { return }

        Logger.info("Transferring file \(self.file.identifier) \(currentWholeNumberProgress)%")
    }
}
