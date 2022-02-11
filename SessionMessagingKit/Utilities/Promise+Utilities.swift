// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit

extension Promise where T == Data {
    func decoded<R: Decodable>(as type: R.Type, on queue: DispatchQueue? = nil, error: Error? = nil) -> Promise<R> {
        self.map(on: queue) { data -> R in
            try data.decoded(as: type, customError: error)
        }
    }
}
