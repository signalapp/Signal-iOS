// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionUtilitiesKit

extension OpenGroupAPI {
    @objc(SOGSServer)
    public final class Server: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        @objc public let name: String
        public let capabilities: Capabilities

        public init(
            name: String,
            capabilities: Capabilities
        ) {
            self.name = name.lowercased()
            self.capabilities = capabilities
        }

        // MARK: - Coding
        
        public init?(coder: NSCoder) {
            let capabilitiesString: [String] = coder.decodeObject(forKey: "capabilities") as! [String]
            let missingCapabilitiesString: [String]? = coder.decodeObject(forKey: "missingCapabilities") as? [String]
            
            name = coder.decodeObject(forKey: "name") as! String
            capabilities = Capabilities(
                capabilities: capabilitiesString.map { Capabilities.Capability(from: $0) },
                missing: missingCapabilitiesString?.map { Capabilities.Capability(from: $0) }
            )
            
            super.init()
        }

        public func encode(with coder: NSCoder) {
            coder.encode(name, forKey: "name")
            coder.encode(capabilities.capabilities.map { $0.rawValue }, forKey: "capabilities")
            coder.encode(capabilities.missing?.map { $0.rawValue }, forKey: "missingCapabilities")
        }

        override public var description: String {
            "\(name) (Capabilities: [\(capabilities.capabilities.map { $0.rawValue }.joined(separator: ", "))], Missing: [\((capabilities.missing ?? []).map { $0.rawValue }.joined(separator: ", "))])"
        }
    }
}
