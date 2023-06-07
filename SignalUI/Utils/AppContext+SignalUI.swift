//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class AppContextUtils {

    private init() {}

    public static func openSystemSettingsAction(completion: (() -> Void)? = nil) -> ActionSheetAction? {
        guard CurrentAppContext().isMainApp else {
            return nil
        }

        return ActionSheetAction(title: CommonStrings.openSettingsButton,
                                 accessibilityIdentifier: "system_settings",
                                 style: .default) { _ in
            CurrentAppContext().openSystemSettings()
            completion?()
        }
    }
}
