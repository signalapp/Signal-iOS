// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine

public extension AnyPublisher {
    func firstValue() -> Output? {
        var value: Output?
        
        _ = self
            .receiveOnMain(immediately: true)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { result in value = result }
            )
        
        return value
    }
}
