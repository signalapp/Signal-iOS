//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

public extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public extension Array {
    func chunked(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}

/// Like the built-in `zip` but works with arbitrarily many arrays.
/*
     let input = [[a1, a2, a3, a4],
                  [b1, b2, b3, b4],
                  [c1, c2, c3, c4]]

     transpose(input)
         -> [[a1, b1, c1],
             [a2, b2, c2],
             [a3, b3, c3],
             [a4, b4, c4]]
 */
public func transpose<T>(_ arrays: [[T]]) -> [[T]] {
    guard let firstArray = arrays.first else {
        return [[]]
    }

    var minCount: Int = firstArray.count
    for array in arrays {
        // we could remove this check and zip to the shortest length
        // but typically we want to zip identical length arrays.
        assert(minCount == array.count)
        minCount = min(minCount, array.count)
    }

    var output: [[T]] = []
    for i in 0..<minCount {
        output.append(arrays.map { $0[i] })
    }

    return output
}
