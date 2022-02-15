// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension String {
    public func dataFromHex() -> Data? {
        guard self.count > 0 && (self.count % 2) == 0 else { return nil }

        let chars = self.map { $0 }
        let bytes: [UInt8] = stride(from: 0, to: chars.count, by: 2)
            .map { index -> String in String(chars[index]) + String(chars[index + 1]) }
            .compactMap { (str: String) -> UInt8? in UInt8(str, radix: 16) }
        
        guard (self.count / bytes.count) == 2 else { return nil }
        
        return Data(bytes)
    }
}
