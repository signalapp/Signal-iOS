import Foundation

internal extension String {

    func removingPrefix(_ prefix: String) -> String {
        guard let range = self.range(of: prefix), range.lowerBound == startIndex else { return self }
        return String(self[range.upperBound..<endIndex])
    }
}
