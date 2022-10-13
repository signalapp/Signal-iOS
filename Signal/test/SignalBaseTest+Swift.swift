//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension SignalBaseTest {
    func read<T>(block: @escaping (SDSAnyReadTransaction) -> T) -> T {
        return databaseStorage.read(block: block)
    }

    func read<T>(block: @escaping (SDSAnyReadTransaction) throws -> T) throws -> T {
        return try databaseStorage.read(block: block)
    }

    func write<T>(block: @escaping (SDSAnyWriteTransaction) -> T) -> T {
        return databaseStorage.write(block: block)
    }

    func write<T>(block: @escaping (SDSAnyWriteTransaction) throws -> T) throws -> T {
        return try databaseStorage.write(block: block)
    }
}
