//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class DownloadStickerOperation: OWSOperation {

    private let success: (Data) -> Void
    private let failure: (Error) -> Void
    private let stickerInfo: StickerInfo

    @objc public required init(stickerInfo: StickerInfo,
                               success : @escaping (Data) -> Void,
                               failure : @escaping (Error) -> Void) {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        self.success = success
        self.failure = failure
        self.stickerInfo = stickerInfo

        super.init()

        self.remainingRetries = 10
    }

    // MARK: Dependencies

    private var cdnSessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
    }

    override public func run() {

        if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
            Logger.verbose("Skipping redundant operation.")
            let error = StickerError.redundantOperation as NSError
            error.isRetryable = false
            return reportError(error)
        }

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"
        cdnSessionManager.get(urlPath,
                              parameters: nil,
                              progress: { (_) in
                                // Do nothing.
        },
                              success: { [weak self] (_, response) in
                                guard let self = self else {
                                    return
                                }
                                guard let data = response as? Data else {
                                    owsFailDebug("Unexpected response: \(type(of: response))")
                                    return
                                }
                                Logger.verbose("Download succeeded.")

                                do {
                                    let plaintext = try StickerManager.decrypt(ciphertext: data, packKey: self.stickerInfo.packKey)
                                    Logger.verbose("Decryption succeeded.")

                                    self.success(plaintext)
                                    self.reportSuccess()
                                } catch let error as NSError {
                                    owsFailDebug("Decryption failed: \(error)")

                                    // Fail immediately; do not retry.
                                    error.isRetryable = false
                                    return self.reportError(error)
                                }
            },
                              failure: { [weak self] (_, error) in
                                guard let self = self else {
                                    return
                                }
                                Logger.error("Download failed: \(error)")

                                // TODO: We need to discriminate retry-able errors from
                                //       404s, etc.  We might want to abort on all 4xx and 5xx.
                                let errorCopy = error as NSError
                                errorCopy.isRetryable = true
                                self.reportError(errorCopy)
        })
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        failure(error)
    }

    override public func retryInterval() -> TimeInterval {
        // Arbitrary backoff factor...
        // With backOffFactor of 1.9
        // try  1 delay:  0.00s
        // try  2 delay:  0.19s
        // ...
        // try  5 delay:  1.30s
        // ...
        // try 11 delay: 61.31s
        let backoffFactor = 1.9
        let maxBackoff = kHourInterval

        let seconds = 0.1 * min(maxBackoff, pow(backoffFactor, Double(self.errorCount)))
        return seconds
    }
}
