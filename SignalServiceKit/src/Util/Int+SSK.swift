//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension Int {
    var abbreviatedString: String {
        let value: Double
        let suffix: String
        switch abs(self) {
        case 1_000..<1_000_000:
            value = Double(self) / 1_000
            suffix = "K"
        case 1_000_000..<1_000_000_000:
            value = Double(self) / 1_000_000
            suffix = "M"
        case 1_000_000_000...Int.max:
            value = Double(self) / 1_000_000_000
            suffix = "B"
        default:
            value = Double(self)
            suffix = ""
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.negativeSuffix = suffix
        numberFormatter.positiveSuffix = suffix

        guard let result = numberFormatter.string(for: value) else {
            owsFailDebug("unexpectedly failed to format number")
            return "\(self)"
        }

        return result
    }
}
