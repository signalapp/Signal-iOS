//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

final public class AppContextUtils {

    private init() {}

    public static func openSystemSettingsAction(completion: (() -> Void)? = nil) -> ActionSheetAction? {
        guard CurrentAppContext().isMainApp else {
            return nil
        }

        return ActionSheetAction(title: CommonStrings.openSystemSettingsButton) { _ in
            CurrentAppContext().openSystemSettings()
            completion?()
        }
    }
}
