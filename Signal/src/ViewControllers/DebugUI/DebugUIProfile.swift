//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class DebugUIProfile: DebugUIPage {

    let TAG = "[DebugUIProfile]"

    // MARK: Dependencies

    var messageSender: MessageSender {
        return Environment.getCurrent().messageSender
    }
    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: Overrides

    override func name() -> String {
        return "Profile"
    }

    override func section(thread aThread: TSThread?) -> OWSTableSection? {
        let sectionItems = [
            OWSTableItem(title: "Clear Profile Whitelist") {
                self.profileManager.clearProfileWhitelist()
            },
            OWSTableItem(title: "Log Profile Whitelist") {
                self.profileManager.logProfileWhitelist()
            },
            OWSTableItem(title: "Log User Profiles") {
                self.profileManager.logUserProfiles()
            },
            OWSTableItem(title: "Regenerate Profile/ProfileKey") {
                self.profileManager.regenerateLocalProfile()
            },
            OWSTableItem(title: "Send Profile Key Message") {
                let message = OWSProfileKeyMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: aThread)
                self.messageSender.sendPromise(message: message).then {
                    Logger.info("Successfully sent profile key message to thread: \(String(describing: aThread))")
                    }.catch { _ in
                        owsFail("Failed to send profile key message to thread: \(String(describing: aThread))")
                }
            }
        ]

        return OWSTableSection(title: "Profile", items: sectionItems)
    }

}
