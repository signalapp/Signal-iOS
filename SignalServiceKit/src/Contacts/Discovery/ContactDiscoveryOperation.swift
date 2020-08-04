//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

/// This would be a struct if it didn't need to be bridged to objc.
/// A plain-old tuple of contact info. This is not cached or updated like SignalServiceAddress
@objc (OWSDiscoveredContactInfo) @objcMembers
public class DiscoveredContactInfo: NSObject {
    public let e164: String?
    public let uuid: UUID?

    public init(e164: String?, uuid: UUID?) {
        self.e164 = e164
        self.uuid = uuid
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherInfo = object as? DiscoveredContactInfo else { return false }
        return e164 == otherInfo.e164 && uuid == otherInfo.uuid
    }

    public override var hash: Int {
        return e164.hashValue ^ uuid.hashValue
    }
}

@objc (OWSContactDiscovering)
public protocol ContactDiscovering {
    /// Constructs a ContactDiscovering object from an array of e164 phone numbers
    @objc init(phoneNumbersToLookup: [String])

    /// On successful completion, this property will be populated with the resulting contact info
    @objc var discoveredContactInfo: Set<DiscoveredContactInfo>? { get }
}

enum ContactDiscoveryError: Error {
    case parseError(description: String)
    case assertionError(description: String)
    case clientError(underlyingError: Error)
    case serverError(underlyingError: Error)
}
