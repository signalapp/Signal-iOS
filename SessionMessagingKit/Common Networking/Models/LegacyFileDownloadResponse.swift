// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

struct LegacyFileDownloadResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case base64EncodedData = "result"
    }
    
    let data: Data
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(data.base64EncodedString(), forKey: .base64EncodedData)
    }
}

// MARK: - Decoder

extension LegacyFileDownloadResponse {
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        let base64EncodedData: String = try container.decode(String.self, forKey: .base64EncodedData)
        
        guard let data = Data(base64Encoded: base64EncodedData) else {
            throw FileServerAPIV2.Error.parsingFailed
        }
        
        self = LegacyFileDownloadResponse(
            data: data
        )
    }
}
