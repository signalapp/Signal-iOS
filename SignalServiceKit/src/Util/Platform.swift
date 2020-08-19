//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class Platform: NSObject {

    @objc
    public static let isSimulator: Bool = {
        let isSim: Bool
        #if targetEnvironment(simulator)
            isSim = true
        #else
            isSim = false
        #endif
        return isSim
    }()
}
