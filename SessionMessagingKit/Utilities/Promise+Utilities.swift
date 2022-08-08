// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

extension Promise where T == Data {
    func decoded<R: Decodable>(as type: R.Type, on queue: DispatchQueue? = nil, using dependencies: Dependencies = Dependencies()) -> Promise<R> {
        self.map(on: queue) { data -> R in
            try data.decoded(as: type, using: dependencies)
        }
    }
}

extension Promise where T == (OnionRequestResponseInfoType, Data?) {
    func decoded<R: Decodable>(as type: R.Type, on queue: DispatchQueue? = nil, using dependencies: Dependencies = Dependencies()) -> Promise<(OnionRequestResponseInfoType, R)> {
        self.map(on: queue) { responseInfo, maybeData -> (OnionRequestResponseInfoType, R) in
            guard let data: Data = maybeData else { throw HTTP.Error.parsingFailed }
            
            do {
                return (responseInfo, try data.decoded(as: type, using: dependencies))
            }
            catch {
                throw HTTP.Error.parsingFailed
            }
        }
    }
}
