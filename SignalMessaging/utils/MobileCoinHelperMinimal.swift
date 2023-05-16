//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import MobileCoinMinimal

public class MobileCoinHelperMinimal: MobileCoinHelper {

    public init() { }

    public func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo {
        let txOutPublicKey = try MobileCoinMinimal.txOutPublicKey(forReceiptData: receiptData)
        return MobileCoinReceiptInfo(txOutPublicKey: txOutPublicKey)
    }

    public func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool {
        MobileCoinMinimal.isValidMobileCoinPublicAddress(addressData)
    }
}
