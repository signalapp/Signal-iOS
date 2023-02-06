//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(FullTextSearchFinder)
public class FullTextSearchFinderForObjC: NSObject {
    @objc(modelWasUpdated:transaction:)
    public static func modelWasUpdated(model: AnyObject, transaction: SDSAnyWriteTransaction) {
        guard let model = model as? SDSIndexableModel else {
            owsFailDebug("Invalid model.")
            return
        }
        FullTextSearchFinder.modelWasUpdated(model: model, transaction: transaction)
    }
}
