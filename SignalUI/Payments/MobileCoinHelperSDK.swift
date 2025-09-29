//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import MobileCoin

final public class MobileCoinHelperSDK: MobileCoinHelper {

    public init() { }

    public func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo {
        guard let receipt = MobileCoin.Receipt(serializedData: receiptData) else {
            throw OWSAssertionError("Invalid receipt.")
        }
        return MobileCoinReceiptInfo(txOutPublicKey: receipt.txOutPublicKey)
    }

    public func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool {
        MobileCoin.PublicAddress(serializedData: addressData) != nil
    }
}
