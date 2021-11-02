//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol MobileCoinHelper: AnyObject {
    func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo

    func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool
}

// MARK: -

@objc
public class MobileCoinReceiptInfo: NSObject {
    public let txOutPublicKey: Data

    public required init(txOutPublicKey: Data) {
        self.txOutPublicKey = txOutPublicKey
    }
}

// MARK: -

@objc
public class MobileCoinHelperMock: NSObject, MobileCoinHelper {
    public func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo {
        throw OWSAssertionError("Not implemented.")
    }

    public func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool {
        false
    }
}
