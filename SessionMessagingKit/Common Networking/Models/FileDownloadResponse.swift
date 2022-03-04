// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

// TODO: Update this (looks like it's getting changed to just be the data, the properties are send through as headers)
public struct FileDownloadResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case fileName = "filename"
        case size
        case uploaded
        case expires
        case base64EncodedData = "result"   // TODO: Confirm the name of this value
    }
    
    public let fileName: String
    public let size: Int64
    public let uploaded: TimeInterval
    public let expires: TimeInterval?
    public let data: Data
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fileName, forKey: .fileName)
        try container.encode(size, forKey: .size)
        try container.encode(uploaded, forKey: .uploaded)
        try container.encodeIfPresent(expires, forKey: .expires)
        try container.encode(data.base64EncodedString(), forKey: .base64EncodedData)
    }
}

// MARK: - Decoder

extension FileDownloadResponse {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        let base64EncodedData: String = try container.decode(String.self, forKey: .base64EncodedData)
        
        guard let data = Data(base64Encoded: base64EncodedData) else { throw HTTP.Error.parsingFailed }
        
        self = FileDownloadResponse(
            fileName: try container.decode(String.self, forKey: .fileName),
            size: try container.decode(Int64.self, forKey: .size),
            uploaded: try container.decode(TimeInterval.self, forKey: .uploaded),
            expires: try? container.decode(TimeInterval.self, forKey: .expires),
            data: data
        )
    }
}
