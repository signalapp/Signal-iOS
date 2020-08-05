//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

struct DiscoveredContactInfo: Hashable {
    let e164: String?
    let uuid: UUID?

    init(e164: String?, uuid: UUID?) {
        self.e164 = e164
        self.uuid = uuid
    }
}

/// An item that fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTask. You probably don't want to use this directly.
protocol ContactDiscovering {
    /// Constructs a ContactDiscovering object from a set of e164 phone numbers
    init(phoneNumbersToLookup: Set<String>)

    /// Returns a promise that performs ContactDiscovery on the provided queue
    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>>
}

enum ContactDiscoveryError: Error {
    case parseError(description: String)
    case assertionError(description: String)
    case clientError(underlyingError: Error)
    case serverError(underlyingError: Error)
}
