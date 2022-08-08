// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

// MARK: - Decoding

extension Dependencies {
    static let userInfoKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "io.oxen.dependencies.codingOptions")!
}

public extension Data {
    func decoded<T: Decodable>(as type: T.Type, using dependencies: Dependencies = Dependencies()) throws -> T {
        do {
            let decoder: JSONDecoder = JSONDecoder()
            decoder.userInfo = [ Dependencies.userInfoKey: dependencies ]
            
            return try decoder.decode(type, from: self)
        }
        catch {
            throw HTTP.Error.parsingFailed
        }
    }
}
