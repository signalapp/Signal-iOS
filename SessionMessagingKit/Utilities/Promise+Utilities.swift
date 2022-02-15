// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit

extension Promise where T == Data {
    func decoded<R: Decodable>(as type: R.Type, on queue: DispatchQueue? = nil, error: Error? = nil) -> Promise<R> {
        self.map(on: queue) { data -> R in
            try data.decoded(as: type, customError: error)
        }
    }
}

extension Promise where T == (OnionRequestResponseInfoType, Data?) {
    func decoded<R: Decodable>(as type: R.Type, on queue: DispatchQueue? = nil, error: Error? = nil) -> Promise<(OnionRequestResponseInfoType, R)> {
        self.map(on: queue) { responseInfo, maybeData -> (OnionRequestResponseInfoType, R) in
            guard let data: Data = maybeData else {
                throw OpenGroupAPIV2.Error.parsingFailed
            }
            
            return (responseInfo, try data.decoded(as: type, customError: error))
        }
    }
}
