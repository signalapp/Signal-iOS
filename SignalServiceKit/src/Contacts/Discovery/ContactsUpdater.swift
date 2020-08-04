//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension ContactsUpdater {
    func lookupIdentifiersPromise(phoneNumbers: [String]) -> Promise<[SignalRecipient]> {
        let (promise, resolver) = Promise<[SignalRecipient]>.pending()
        self.lookupIdentifiers(phoneNumbers,
                               success: resolver.fulfill,
                               failure: resolver.reject)
        return promise
    }
}
