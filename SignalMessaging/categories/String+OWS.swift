//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension String {

    var stripped: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Truncates string to be less than or equal to byteCount, while ensuring we never truncate partial characters for multibyte characters.
    func truncated(toByteCount byteCount: UInt) -> String? {
        var lowerBoundCharCount = 0
        var upperBoundCharCount = self.count

        while (lowerBoundCharCount < upperBoundCharCount) {
            guard let upperBoundData = self.prefix(upperBoundCharCount).data(using: .utf8) else {
                owsFailDebug("upperBoundData was unexpectedly nil")
                return nil
            }

            if upperBoundData.count <= byteCount {
                break
            }

            // converge
            if upperBoundCharCount - lowerBoundCharCount == 1 {
                upperBoundCharCount = lowerBoundCharCount
                break
            }

            let midpointCharCount = (lowerBoundCharCount + upperBoundCharCount) / 2
            let midpointString = self.prefix(midpointCharCount)

            guard let midpointData = midpointString.data(using: .utf8) else {
                owsFailDebug("midpointData was unexpectedly nil")
                return nil
            }
            let midpointByteCount = midpointData.count

            if midpointByteCount < byteCount {
                lowerBoundCharCount = midpointCharCount
            } else {
                upperBoundCharCount = midpointCharCount
            }
        }

        return String(self.prefix(upperBoundCharCount))
    }

}
