//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum NetworkInterface: UInt, Equatable, CaseIterable {
    case cellular = 0
    case wifi

    var singleItemSet: NetworkInterfaceSet {
        NetworkInterfaceSet(rawValue: 1 << rawValue)
    }
}

public struct NetworkInterfaceSet: OptionSet, Equatable {
    public let rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let none: NetworkInterfaceSet = []
    public static let cellular = NetworkInterface.cellular.singleItemSet
    public static let wifi = NetworkInterface.wifi.singleItemSet
    public static let wifiAndCellular: NetworkInterfaceSet = [.cellular, .wifi]

    public var inverted: NetworkInterfaceSet {
        let invertedRawValue = rawValue ^ Self.wifiAndCellular.rawValue
        return NetworkInterfaceSet(rawValue: invertedRawValue)
    }
}
