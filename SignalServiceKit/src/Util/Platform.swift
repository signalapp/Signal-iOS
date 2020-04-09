//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class Platform: NSObject {

    @objc
    public static let isSimulator: Bool = {
        let isSim: Bool
        #if arch(i386) || arch(x86_64)
            isSim = true
        #else
            isSim = false
        #endif
        return isSim
    }()
}
