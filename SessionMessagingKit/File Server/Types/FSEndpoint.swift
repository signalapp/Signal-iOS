// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension FileServerAPI {
    public enum Endpoint: EndpointType {
        case file
        case fileIndividual(fileId: String)
        case sessionVersion
        
        var path: String {
            switch self {
                case .file: return "file"
                case .fileIndividual(let fileId): return "file/\(fileId)"
                case .sessionVersion: return "session_version"
            }
        }
    }
}
