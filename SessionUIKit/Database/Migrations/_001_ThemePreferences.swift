// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration extracts an old theme preference from UserDefaults and saves it to the database as well as set the default for the other
/// theme preferences
enum _001_ThemePreferences: Migration {
    static let target: TargetMigrations.Identifier = .uiKit
    static let identifier: String = "ThemePreferences"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: Database) throws {
        // Determine if the user was matching the system setting
        let isMatchingSystemSetting: Bool = UserDefaults.standard.dictionaryRepresentation()
            .keys
            .contains("appMode")
        
        // Set the default theme settings sccordingly
        db[.themeMatchSystemDayNightCycle] = isMatchingSystemSetting
        db[.theme] = (isMatchingSystemSetting ?
            Theme.classicDark :
            (UserDefaults.standard.integer(forKey: "appMode") == 0 ?
                Theme.classicLight :
                Theme.classicDark
            )
        )
        db[.themePrimaryColor] = Theme.PrimaryColor.green
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}
