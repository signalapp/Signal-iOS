//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

class GroupsV2AvatarDownloadOperation: CDNDownloadOperation {

    private let urlPath: String
    private let maxDownloadSize: UInt?
    public let promise: Promise<Data>
    private let resolver: Resolver<Data>

    public required init(urlPath: String,
                         maxDownloadSize: UInt? = nil) {
        self.urlPath = urlPath
        self.maxDownloadSize = maxDownloadSize

        let (promise, resolver) = Promise<Data>.pending()
        self.promise = promise
        self.resolver = resolver

        super.init()
    }

    override public func run() {
        firstly {
            return try tryToDownload(urlPath: urlPath, maxDownloadSize: maxDownloadSize)
        }.done(on: DispatchQueue.global()) { [weak self] data in
            guard let self = self else {
                return
            }

            self.resolver.fulfill(data)
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

        resolver.reject(error)
    }
}
