// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

struct Failable<T: Codable>: Codable {
    let value: T?
    
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            self.value = nil
            return
        }
        
        self.value = try? container.decode(T.self)
    }
    
    func encode(to encoder: Encoder) throws {
        guard let value: T = value else { return }
        
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        
        try container.encode(value)
    }
}
