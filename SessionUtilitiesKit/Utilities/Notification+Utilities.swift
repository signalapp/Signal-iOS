// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension Notification {
    public struct Key: RawRepresentable, Hashable, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral, ExpressibleByStringLiteral {
        public typealias RawValue = String
        
        public var rawValue: String
        
        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
        
        // MARK: - RawRepresentable
        
        public init?(rawValue: String) {
            self.rawValue = rawValue
        }
        
        // MARK: - ExpressibleByStringLiteral
        
        public init(stringLiteral value: String) {
            self.rawValue = value
        }
        
        // MARK: - ExpressibleByExtendedGraphemeClusterLiteral
        
        public init(extendedGraphemeClusterLiteral value: String) {
            self.rawValue = value
        }
        
        // MARK: - ExpressibleByUnicodeScalarLiteral
        
        public init(unicodeScalarLiteral value: String) {
            self.rawValue = value
        }
    }
}
