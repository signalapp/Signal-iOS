//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class DebugUIProfile: DebugUIPage {

    // MARK: Dependencies

    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }
    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: Overrides

    override func name() -> String {
        return "Profile"
    }

    override func section(thread aThread: TSThread?) -> OWSTableSection? {
        let profileManager = self.profileManager
        let sectionItems = [
            OWSTableItem(title: "Clear Profile Whitelist") {
                profileManager.clearProfileWhitelist()
            },
            OWSTableItem(title: "Log Profile Whitelist") {
                profileManager.logProfileWhitelist()
            },
            OWSTableItem(title: "Log User Profiles") {
                profileManager.logUserProfiles()
            },
            OWSTableItem(title: "Regenerate Profile/ProfileKey") {
                profileManager.regenerateLocalProfile()
            },
            OWSTableItem(title: "Send Profile Key Message") { [weak self] in
                guard let strongSelf = self else { return }

                let message = OWSProfileKeyMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: aThread)
                strongSelf.messageSender.sendPromise(message: message).then {
                    Logger.info("Successfully sent profile key message to thread: \(String(describing: aThread))")
                    }.catch { _ in
                        owsFailDebug("Failed to send profile key message to thread: \(String(describing: aThread))")
                }
            }
        ]

        return OWSTableSection(title: "Profile", items: sectionItems)
    }

}
