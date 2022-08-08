// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct Capabilities: Codable, Equatable {
        public let capabilities: [Capability.Variant]
        public let missing: [Capability.Variant]?

        // MARK: - Initialization

        public init(capabilities: [Capability.Variant], missing: [Capability.Variant]? = nil) {
            self.capabilities = capabilities
            self.missing = missing
        }
    }
}
