//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Result where Failure == Error {
    public init(catching block: () async throws -> Success) async {
        do {
            self = .success(try await block())
        } catch {
            self = .failure(error)
        }
    }
}

extension Result {

    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
