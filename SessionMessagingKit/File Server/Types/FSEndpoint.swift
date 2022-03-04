// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension FileServerAPIV2 {
    public enum Endpoint: EndpointType {
        case files
        case file(fileId: UInt64)
        case sessionVersion
        
        var path: String {
            switch self {
                case .files: return "files"
                case .file(let fileId): return "files/\(fileId)"
                case .sessionVersion: return "session_version"
            }
        }
    }
}
