//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc public class ExperienceUpgrade: TSYapDatabaseObject {

    @objc
    public override init(uniqueId: String?) {
        super.init(uniqueId: uniqueId)
    }

   @objc public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
}
