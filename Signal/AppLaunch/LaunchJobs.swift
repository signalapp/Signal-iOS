//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

enum LaunchJobs {
    static func run(databaseStorage: SDSDatabaseStorage) async {
        // Getting this work done ASAP is super high priority since we won't finish
        // launching until the completion block is fired.
        //
        // Originally, I considered making this all synchronous on the main thread,
        // but I figured that in the absolute *worst* case where this work takes
        // ~15s we risk getting watchdogged by SpringBoard.

        // Mark all "attempting out" messages as "unsent", i.e. any messages that
        // were not successfully sent before the app exited should be marked as
        // failures.
        await FailedMessagesJob().run(databaseStorage: databaseStorage)
        // Mark all "incomplete" calls as missed, e.g. any incoming or outgoing
        // calls that were not connected, failed or hung up before the app existed
        // should be marked as missed.
        await IncompleteCallsJob().run(databaseStorage: databaseStorage)
    }
}
