//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class AppActivePrecondition: Precondition {
    private let appContext: AppContext
    init(appContext: AppContext) {
        self.appContext = appContext
    }

    @MainActor
    func waitUntilSatisfied() async -> WaitResult {
        if appContext.isAppForegroundAndActive() {
            return .satisfiedImmediately
        }
        await NotificationCenter.default.observeOnce(UIApplication.didBecomeActiveNotification)
        return .wasNotSatisfiedButIsNow
    }
}
