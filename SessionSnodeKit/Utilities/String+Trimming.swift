import Foundation

internal extension String {

    func removingPrefix(_ prefix: String, if condition: Bool = true) -> String {
        guard condition else { return self }
        guard let range = self.range(of: prefix), range.lowerBound == startIndex else { return self }
        
        return String(self[range.upperBound..<endIndex])
    }
}

internal extension String {
    func appending(_ other: String?) -> String {
        guard let value: String = other else { return self }
        
        return self.appending(value)
    }
}
