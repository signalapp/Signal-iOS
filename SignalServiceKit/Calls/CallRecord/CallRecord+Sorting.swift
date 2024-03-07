//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension CallRecord {
    enum SortDirection {
        case ascending
        case descending

        fileprivate func compareForSort(lhs: CallRecord, rhs: CallRecord) -> Bool {
            switch self {
            case .ascending:
                return lhs.callBeganTimestamp < rhs.callBeganTimestamp
            case .descending:
                return lhs.callBeganTimestamp > rhs.callBeganTimestamp
            }
        }
    }
}

public extension Array<CallRecord> {
    func isSortedByTimestamp(_ direction: CallRecord.SortDirection) -> Bool {
        return sorted(by: direction.compareForSort(lhs:rhs:)).enumerated().allSatisfy { (idx, callRecord) in
            /// When sorted by timestamp descending the order should not have
            /// changed; i.e., each enumerated sorted call record is exactly the
            /// same as the unsorted call record in the same index.
            callRecord === self[idx]
        }
    }
}
