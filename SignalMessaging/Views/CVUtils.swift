//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVUtils {

    @available(*, unavailable, message: "use other init() instead.")
    private init() {}

    public static let workQueue: DispatchQueue = {
        // Note that we use the highest qos.
        DispatchQueue(label: "org.whispersystems.signal.conversationView",
                             qos: .userInteractive,
                             autoreleaseFrequency: .workItem)
    }()
}
