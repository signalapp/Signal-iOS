//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol MobileCoinHelper: AnyObject {
    func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo

    func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool
}

// MARK: -

public class MobileCoinReceiptInfo {
    public let txOutPublicKey: Data

    public init(txOutPublicKey: Data) {
        self.txOutPublicKey = txOutPublicKey
    }
}

// MARK: -

public class MobileCoinHelperMock: MobileCoinHelper {
    public func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo {
        throw OWSAssertionError("Not implemented.")
    }

    public func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool {
        false
    }
}
