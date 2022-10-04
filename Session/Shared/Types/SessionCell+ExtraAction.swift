// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension SessionCell {
    struct ExtraAction: Hashable, Equatable {
        let title: String
        let onTap: (() -> Void)
        
        // MARK: - Conformance
        
        public func hash(into hasher: inout Hasher) {
            title.hash(into: &hasher)
        }
        
        static func == (lhs: SessionCell.ExtraAction, rhs: SessionCell.ExtraAction) -> Bool {
            return (lhs.title == rhs.title)
        }
    }
}
