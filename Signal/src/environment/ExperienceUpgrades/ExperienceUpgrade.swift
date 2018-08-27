//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc public class ExperienceUpgrade: TSYapDatabaseObject {
    let title: String
    let body: String
    let image: UIImage?

    @objc public required init(uniqueId: String, title: String, body: String, image: UIImage) {
        self.title = title
        self.body = body
        self.image  = image
        super.init(uniqueId: uniqueId)
    }

    @objc public override required init(uniqueId: String?) {
        // This is the unfortunate seam between strict swift and fast-and-loose objc
        // we can't leave these properties nil, since we really "don't know" that the superclass
        // will assign them.
        self.title = "New Feature"
        self.body = "Bug fixes and performance improvements."
        self.image = nil
        super.init(uniqueId: uniqueId)
    }

   @objc public required init!(coder: NSCoder) {
        // This is the unfortunate seam between strict swift and fast-and-loose objc
        // we can't leave these properties nil, since we really "don't know" that the superclass
        // will assign them.
        self.title = "New Feature"
        self.body = "Bug fixes and performance improvements."
        self.image = nil
        super.init(coder: coder)
    }

    @objc public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        // This is the unfortunate seam between strict swift and fast-and-loose objc
        // we can't leave these properties nil, since we really "don't know" that the superclass
        // will assign them.
        self.title = "New Feature"
        self.body = "Bug fixes and performance improvements."
        self.image = nil
        try super.init(dictionary: dictionaryValue)
    }

    @objc public override class func storageBehaviorForProperty(withKey propertyKey: String) -> MTLPropertyStorage {
        // These exist in a hardcoded set - no need to save them, plus it allows us to
        // update copy/image down the line if there was a typo and we want to re-expose
        // these models in a "change log" archive.
        if propertyKey == "title" || propertyKey == "body" || propertyKey == "image" {
            return MTLPropertyStorageNone
        } else if propertyKey == "uniqueId" || propertyKey == "seenAt" {
            return super.storageBehaviorForProperty(withKey: propertyKey)
        } else {
            // Being conservative here in case we rename a property.
            owsFailDebug("unknown property \(propertyKey)")
            return super.storageBehaviorForProperty(withKey: propertyKey)
        }
    }
}
