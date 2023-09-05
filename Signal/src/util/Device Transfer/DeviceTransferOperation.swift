//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit

class DeviceTransferOperation: OWSOperation {

    public struct CancelError: Error {}

    let file: DeviceTransferProtoFile

    let promise: Promise<Void>
    private let future: Future<Void>

    class func scheduleTransfer(file: DeviceTransferProtoFile, priority: Operation.QueuePriority = .normal) -> Promise<Void> {
        let operation = DeviceTransferOperation(file: file)
        operationQueue.addOperation(operation)
        return operation.promise
    }

    class func cancelAllOperations() { operationQueue.cancelAllOperations() }

    private static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = logTag()
        queue.maxConcurrentOperationCount = 10
        return queue
    }()

    private init(file: DeviceTransferProtoFile) {
        self.file = file
        (self.promise, self.future) = Promise<Void>.pending()
        super.init()
    }

    // MARK: - Run

    override func reportSuccess() {
        super.reportSuccess()
        future.resolve()
    }

    override func didReportError(_ error: Error) {
        super.didReportError(error)
        future.reject(error)
    }

    override func reportCancelled() {
        super.reportCancelled()
        if !future.isSealed {
            future.reject(CancelError())
        }
    }

    override public func run() {
        Logger.info("Transferring file: \(file.identifier), estimatedSize: \(file.estimatedSize)")

        DispatchQueue.global().async { self.prepareForSending() }
    }

    private var progress: Progress?
    private func prepareForSending() {
        guard case .outgoing(let newDevicePeerId, _, _, let transferredFiles, let progress) = deviceTransferService.transferState else {
            return reportError(OWSAssertionError("Tried to transfer file while in unexpected state: \(deviceTransferService.transferState)"))
        }

        guard !transferredFiles.contains(file.identifier) else {
            Logger.info("File was already transferred, skipping")
            return reportSuccess()
        }

        var url = URL(fileURLWithPath: file.relativePath, relativeTo: DeviceTransferService.appSharedDataDirectory)

        if !OWSFileSystem.fileOrFolderExists(url: url) {
            guard ![
                DeviceTransferService.databaseWALIdentifier,
                DeviceTransferService.databaseIdentifier
            ].contains(file.identifier) else {
                return reportError(OWSAssertionError("Mandatory database file is missing for transfer"))
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
                return reportError(OWSAssertionError("Failed to create temp file for missing file \(url)"))
            }
        }

        guard let sha256Digest = try? Cryptography.computeSHA256DigestOfFile(at: url) else {
            return reportError(OWSAssertionError("Failed to calculate sha256 for file"))
        }

        guard let session = deviceTransferService.session else {
            return reportError(OWSAssertionError("Tried to transfer file with no active session"))
        }

        guard let fileProgress = session.sendResource(
            at: url,
            withName: file.identifier + " " + sha256Digest.hexadecimalString,
            toPeer: newDevicePeerId,
            withCompletionHandler: { [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    self.reportError(OWSAssertionError("Transferring file \(self.file.identifier) failed \(error)"))
                } else {
                    Logger.info("Transferring file \(self.file.identifier) complete")
                    self.deviceTransferService.transferState =
                        self.deviceTransferService.transferState.appendingFileId(self.file.identifier)
                    self.reportSuccess()
                }

                self.progress?.removeObserver(self, forKeyPath: "fractionCompleted")
            }
        ) else {
            return reportError(OWSAssertionError("Transfer of file failed \(file.identifier)"))
        }

        progress.addChild(fileProgress, withPendingUnitCount: Int64(file.estimatedSize))
        self.progress = fileProgress
        fileProgress.addObserver(self, forKeyPath: "fractionCompleted", options: .initial, context: nil)
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
