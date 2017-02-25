//  Created by Michael Kirk on 12/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

struct Platform {
    static let isSimulator: Bool = {
        var isSim = false
        #if arch(i386) || arch(x86_64)
            isSim = true
        #endif
        return isSim
    }()
}
