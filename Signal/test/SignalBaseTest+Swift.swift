//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
