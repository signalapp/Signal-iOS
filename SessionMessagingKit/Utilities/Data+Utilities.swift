// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

// MARK: - Decoding

extension OpenGroupAPI.Dependencies {
    static let userInfoKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "io.oxen.dependencies.codingOptions")!
}

public extension Data {
    func decoded<T: Decodable>(as type: T.Type, using dependencies: OpenGroupAPI.Dependencies = OpenGroupAPI.Dependencies()) throws -> T {
        do {
            let decoder: JSONDecoder = JSONDecoder()
            decoder.userInfo = [ OpenGroupAPI.Dependencies.userInfoKey: dependencies ]
            
            return try decoder.decode(type, from: self)
        }
        catch {
            throw HTTP.Error.parsingFailed
        }
    }
}
