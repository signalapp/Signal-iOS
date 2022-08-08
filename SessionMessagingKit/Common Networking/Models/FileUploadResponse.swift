// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

public struct FileUploadResponse: Codable {
    public let id: String
}

// MARK: - Codable

extension FileUploadResponse {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        // Note: SOGS returns an 'int' value but we want to avoid handling both cases so parse
        // that and convert the value to a string so we can be consistent (SOGS is able to handle
        // an array of Strings for the `files` param when posting a message just fine)
        if let intValue: Int64 = try? container.decode(Int64.self, forKey: .id) {
            self = FileUploadResponse(id: "\(intValue)")
            return
        }
        
        self = FileUploadResponse(
            id: try container.decode(String.self, forKey: .id)
        )
    }
}
