//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

func owsFail(_ message: String) {
    Logger.error(message)
    Logger.flush()
    owsFail(message)
}
