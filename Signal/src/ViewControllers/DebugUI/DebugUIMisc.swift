//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIMisc: DebugUIPage {

    let name = "Misc."

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        items += [
            OWSTableItem(title: "Save plaintext database key", actionBlock: {
                DebugUIMisc.enableExternalDatabaseAccess()
            }),

            OWSTableItem(title: "Corrupt username", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    DependenciesBridge.shared.localUsernameManager.setLocalUsernameCorrupted(tx: tx)
                }
            }),

            OWSTableItem(title: "Flag database as corrupted", actionBlock: {
                DebugUIMisc.showFlagDatabaseAsCorruptedUi()
            }),

            OWSTableItem(title: "Test spoiler animations", actionBlock: {
                let viewController = SpoilerAnimationTestController()
                UIApplication.shared.frontmostViewController!.present(viewController, animated: true)
            }),

            OWSTableItem(title: "Test line wrapping stack view", actionBlock: {
                let viewController = LineWrappingStackViewTestController()
                UIApplication.shared.frontmostViewController!.present(viewController, animated: true)
            }),
        ]
        return OWSTableSection(title: name, items: items)
    }

    // MARK: -

    private static func enableExternalDatabaseAccess() {
        guard Platform.isSimulator else {
            OWSActionSheets.showErrorAlert(message: "Must be running in the simulator")
            return
        }
        OWSActionSheets.showConfirmationAlert(
            title: "⚠️⚠️⚠️ Warning!!! ⚠️⚠️⚠️",
            message: "This will save your database key in plaintext and severely weaken the security of " +
                "all data. Make sure you're using a test account with data you don't care about.",
            proceedTitle: "I'm okay with this",
            proceedStyle: .destructive,
            proceedAction: { _ in
                debugOnly_savePlaintextDbKey()
            },
        )
    }

    static func debugOnly_savePlaintextDbKey() {
#if TESTABLE_BUILD && targetEnvironment(simulator)
        // Note: These static strings go hand-in-hand with Scripts/sqlclient.py
        let payload = ["key": SSKEnvironment.shared.databaseStorageRef.keyFetcher.debugOnly_keyData()?.hexadecimalString]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)

        let groupDir = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(), isDirectory: true)
        let destURL = groupDir.appendingPathComponent("dbPayload.txt")
        try! payloadData.write(to: destURL, options: .atomic)
#else
        // This should be caught above. Fatal assert just in case.
        owsFail("Can't savePlaintextDbKey")
#endif
    }

    private static func showFlagDatabaseAsCorruptedUi() {
        OWSActionSheets.showConfirmationAlert(
            title: "Are you sure?",
            message: "This will flag your database as corrupted, which may mean all your data is lost. Are you sure you want to continue?",
            proceedTitle: "Corrupt my database",
            proceedStyle: .destructive,
        ) { _ in
            DatabaseCorruptionState.flagDatabaseAsCorrupted(
                userDefaults: CurrentAppContext().appUserDefaults(),
            )
            owsFail("Crashing due to (intentional) database corruption")
        }
    }
}

#endif
