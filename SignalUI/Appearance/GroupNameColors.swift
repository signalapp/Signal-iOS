//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import UIKit

// MARK: -

/// Represents the "message sender" to "group name color" mapping
/// for a given CVC load.
public struct GroupNameColors {
    fileprivate let colorMap: [SignalServiceAddress: UIColor]
    fileprivate let defaultColor: UIColor

    public func color(for address: SignalServiceAddress) -> UIColor {
        colorMap[address] ?? defaultColor
    }

    fileprivate static var defaultColors: GroupNameColors {
        GroupNameColors(colorMap: [:], defaultColor: Theme.primaryTextColor)
    }

    public static func groupNameColors(forThread thread: TSThread) -> GroupNameColors {
        guard let groupThread = thread as? TSGroupThread else {
            return .defaultColors
        }
        let groupMembership = groupThread.groupMembership
        let values = Self.groupNameColorValues
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        var lastIndex: Int = 0
        var colorMap = [SignalServiceAddress: UIColor]()
        let addresses = Array(groupMembership.fullMembers).stableSort()
        for (index, address) in addresses.enumerated() {
            let valueIndex = index % values.count
            guard let value = values[safe: valueIndex] else {
                owsFailDebug("Invalid values.")
                return .defaultColors
            }
            colorMap[address] = value.color(isDarkThemeEnabled: isDarkThemeEnabled)
            lastIndex = index
        }
        let defaultValueIndex = (lastIndex + 1) % values.count
        guard let defaultValue = values[safe: defaultValueIndex] else {
            owsFailDebug("Invalid values.")
            return .defaultColors
        }
        let defaultColor = defaultValue.color(isDarkThemeEnabled: isDarkThemeEnabled)
        return GroupNameColors(colorMap: colorMap, defaultColor: defaultColor)
    }

    private static var defaultGroupNameColor: UIColor {
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        return Self.groupNameColorValues.first!.color(isDarkThemeEnabled: isDarkThemeEnabled)
    }

    fileprivate struct GroupNameColorValue {
        let lightTheme: UIColor
        let darkTheme: UIColor

        func color(isDarkThemeEnabled: Bool) -> UIColor {
            isDarkThemeEnabled ? darkTheme : lightTheme
        }
    }

    // In descending order of contrast with the other values.
    fileprivate static let groupNameColorValues: [GroupNameColorValue] = [
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x006DA3),
                            darkTheme: UIColor(rgbHex: 0x00A7FA)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x007A3D),
                            darkTheme: UIColor(rgbHex: 0x00B85C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC13215),
                            darkTheme: UIColor(rgbHex: 0xFF6F52)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xB814B8),
                            darkTheme: UIColor(rgbHex: 0xF65AF6)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5B6976),
                            darkTheme: UIColor(rgbHex: 0x8BA1B6)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x3D7406),
                            darkTheme: UIColor(rgbHex: 0x5EB309)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xCC0066),
                            darkTheme: UIColor(rgbHex: 0xF76EB2)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2E51FF),
                            darkTheme: UIColor(rgbHex: 0x8599FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x9C5711),
                            darkTheme: UIColor(rgbHex: 0xD5920B)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x007575),
                            darkTheme: UIColor(rgbHex: 0x00B2B2)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B4D),
                            darkTheme: UIColor(rgbHex: 0xFF6B9C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x8F2AF4),
                            darkTheme: UIColor(rgbHex: 0xBF80FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B0B),
                            darkTheme: UIColor(rgbHex: 0xFF7070)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067906),
                            darkTheme: UIColor(rgbHex: 0x0AB80A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5151F6),
                            darkTheme: UIColor(rgbHex: 0x9494FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x866118),
                            darkTheme: UIColor(rgbHex: 0xD68F00)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067953),
                            darkTheme: UIColor(rgbHex: 0x00B87A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xA20CED),
                            darkTheme: UIColor(rgbHex: 0xCF7CF8)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x4B7000),
                            darkTheme: UIColor(rgbHex: 0x74AD00)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC70A88),
                            darkTheme: UIColor(rgbHex: 0xF76EC9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xB34209),
                            darkTheme: UIColor(rgbHex: 0xF57A3D)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x06792D),
                            darkTheme: UIColor(rgbHex: 0x0AB844)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x7A3DF5),
                            darkTheme: UIColor(rgbHex: 0xAF8AF9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x6B6B24),
                            darkTheme: UIColor(rgbHex: 0xA4A437)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B2C),
                            darkTheme: UIColor(rgbHex: 0xF77389)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2D7906),
                            darkTheme: UIColor(rgbHex: 0x42B309)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xAF0BD0),
                            darkTheme: UIColor(rgbHex: 0xE06EF7)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x32763E),
                            darkTheme: UIColor(rgbHex: 0x4BAF5C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2662D9),
                            darkTheme: UIColor(rgbHex: 0x7DA1E8)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x76681E),
                            darkTheme: UIColor(rgbHex: 0xB89B0A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067462),
                            darkTheme: UIColor(rgbHex: 0x09B397)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x6447F5),
                            darkTheme: UIColor(rgbHex: 0xA18FF9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5E6E0C),
                            darkTheme: UIColor(rgbHex: 0x8FAA09)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x077288),
                            darkTheme: UIColor(rgbHex: 0x00AED1)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC20AA3),
                            darkTheme: UIColor(rgbHex: 0xF75FDD)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2D761E),
                            darkTheme: UIColor(rgbHex: 0x43B42D))
    ]
}
