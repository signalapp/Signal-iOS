//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct ThemeDataStore {

    public enum Appearance: UInt {
        case system
        case light
        case dark
    }

    private enum Keys {
        static var currentMode = "ThemeKeyCurrentMode"
        static var legacyThemeEnabled = "ThemeKeyThemeEnabled"
    }

    private let keyValueStore: KeyValueStore = KeyValueStore(collection: "ThemeCollection")
    public init() { }

    public func getCurrentMode(tx: DBReadTransaction) -> Appearance {
        var currentMode: Appearance = .system
        let hasDefinedMode = keyValueStore.hasValue(Keys.currentMode, transaction: tx)
        if hasDefinedMode {
            let rawMode = keyValueStore.getUInt(
                Keys.currentMode,
                defaultValue: Appearance.system.rawValue,
                transaction: tx,
            )
            if let definedMode = Appearance(rawValue: rawMode) {
                currentMode = definedMode
            }
        } else {
            // If the theme has not yet been defined, check if the user ever manually changed
            // themes in a legacy app version. If so, preserve their selection. Otherwise,
            // default to matching the system theme.
            if keyValueStore.hasValue(Keys.legacyThemeEnabled, transaction: tx) {
                let isLegacyModeDark = keyValueStore.getBool(
                    Keys.legacyThemeEnabled,
                    defaultValue: false,
                    transaction: tx,
                )
                currentMode = isLegacyModeDark ? .dark : .light
            }
        }
        return currentMode
    }

    public func setCurrentMode(_ mode: Appearance, tx: DBWriteTransaction) {
        keyValueStore.setUInt(mode.rawValue, key: Keys.currentMode, transaction: tx)
    }
}
