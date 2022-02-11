// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPIV2 {
    public struct Capabilities: Codable {
        enum Capability: CaseIterable, Codable {
            static var allCases: [Capability] {
                [.pysogs]
            }
            
            case pysogs
            
            /// Fallback case if the capability isn't supported by this version of the app
            case unsupported(String)
            
            // MARK: - Convenience
            
            var rawValue: String {
                switch self {
                    case .unsupported(let originalValue): return originalValue
                    default: return "\(self)"
                }
            }
            
            // MARK: - Codable
            
            init(from decoder: Decoder) throws {
                let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
                let valueString: String = try container.decode(String.self)
                let maybeValue: Capability? = Capability.allCases.first { $0.rawValue == valueString }

                self = (maybeValue ?? .unsupported(valueString))
            }
        }
        
        let capabilities: [Capability]
        let missing: [Capability]?
    }
}
