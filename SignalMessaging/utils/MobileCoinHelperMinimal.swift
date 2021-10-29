//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import MobileCoinMinimal

@objc
public class MobileCoinHelperMinimal: NSObject, MobileCoinHelper {

    public func info(forReceiptData receiptData: Data) throws -> MobileCoinReceiptInfo {
        let txOutPublicKey = try MobileCoinMinimal.txOutPublicKey(forReceiptData: receiptData)
        return MobileCoinReceiptInfo(txOutPublicKey: txOutPublicKey)
    }

    public func isValidMobileCoinPublicAddress(_ addressData: Data) -> Bool {
        MobileCoinMinimal.isValidMobileCoinPublicAddress(addressData)
    }
}
