// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum IdPrefix: String, CaseIterable {
    case standard = "05"    // Used for identified users, open groups, etc.
    case blinded = "15"     // Used for participants in open groups
}
