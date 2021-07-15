//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class AvatarSettingsViewController: OWSTableViewController2 {
    enum Context {
        case groupId(Data)
        case profile
    }

    enum Mode {
        case selection
        case customization(model: AvatarModel)
    }
}

enum AvatarGenerator {

}

// MARK: -
