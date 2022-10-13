//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class GroupsV2AvatarDownloadOperation: CDNDownloadOperation {

    private let urlPath: String
    private let maxDownloadSize: UInt?
    public let promise: Promise<Data>
    private let future: Future<Data>

    public required init(urlPath: String,
                         maxDownloadSize: UInt? = nil) {
        self.urlPath = urlPath
        self.maxDownloadSize = maxDownloadSize

        let (promise, future) = Promise<Data>.pending()
        self.promise = promise
        self.future = future

        super.init()
    }

    override public func run() {
        firstly {
            return try tryToDownload(urlPath: urlPath, maxDownloadSize: maxDownloadSize)
        }.done(on: DispatchQueue.global()) { [weak self] (data: Data) in
            guard let self = self else {
                return
            }

            self.future.resolve(data)
            self.reportSuccess()
        }.catch(on: DispatchQueue.global()) { [weak self] error in
            guard let self = self else {
                return
            }
            return self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didFail(error: Error) {
        Logger.error("Download exhausted retries: \(error)")

        future.reject(error)
    }
}
