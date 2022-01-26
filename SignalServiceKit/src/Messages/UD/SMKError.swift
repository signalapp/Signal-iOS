//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum SMKError: Error {
    case assertionError(description: String)
    case invalidInput(_ description: String)
}
