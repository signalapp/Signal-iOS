// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public enum OnionRequestAPIError: LocalizedError {
    case httpRequestFailedAtDestination(statusCode: UInt, data: Data, destination: OnionRequestAPIDestination)
    case insufficientSnodes
    case invalidURL
    case missingSnodeVersion
    case snodePublicKeySetMissing
    case unsupportedSnodeVersion(String)
    case invalidRequestInfo

    public var errorDescription: String? {
        switch self {
            case .httpRequestFailedAtDestination(let statusCode, let data, let destination):
                if statusCode == 429 { return "Rate limited." }
                if let processedResponseBodyData: Data = OnionRequestAPI.process(bencodedData: data)?.body, let errorResponse: String = String(data: processedResponseBodyData, encoding: .utf8) {
                    return "HTTP request failed at destination (\(destination)) with status code: \(statusCode), error body: \(errorResponse)."
                }
                if let errorResponse: String = String(data: data, encoding: .utf8) {
                    return "HTTP request failed at destination (\(destination)) with status code: \(statusCode), error body: \(errorResponse)."
                }
                
                return "HTTP request failed at destination (\(destination)) with status code: \(statusCode)."
                
            case .insufficientSnodes: return "Couldn't find enough Service Nodes to build a path."
            case .invalidURL: return "Invalid URL"
            case .missingSnodeVersion: return "Missing Service Node version."
            case .snodePublicKeySetMissing: return "Missing Service Node public key set."
            case .unsupportedSnodeVersion(let version): return "Unsupported Service Node version: \(version)."
            case .invalidRequestInfo: return "Invalid Request Info"
        }
    }
}
