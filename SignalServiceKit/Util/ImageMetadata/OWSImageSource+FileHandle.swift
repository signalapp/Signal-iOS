//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import UIKit

public struct FileHandleImageSource: OWSImageSource {

    private let fileHandle: FileHandle
    public let byteLength: Int

    public init(fileHandle: FileHandle, byteLength: Int) {
        self.fileHandle = fileHandle
        self.byteLength = byteLength
    }

    public init(fileUrl: URL) throws {
        let byteLength = Int((try? OWSFileSystem.fileSize(of: fileUrl)) ?? 0)
        let fileHandle = try FileHandle(forReadingFrom: fileUrl)
        self.init(fileHandle: fileHandle, byteLength: byteLength)
    }

    public func readData(byteOffset: Int, byteLength: Int) throws -> Data {
        if try fileHandle.offset() != byteOffset {
            fileHandle.seek(toFileOffset: UInt64(byteOffset))
        }
        return try fileHandle.read(upToCount: byteLength) ?? Data()
    }

    public func cgImageSource() throws -> CGImageSource? {
        let dataProvider = CGDataProvider.from(fileHandle: self.fileHandle, fileSize: Int64(self.byteLength))
        guard let dataProvider else {
            throw OWSAssertionError("couldn't create data provider")
        }
        return CGImageSourceCreateWithDataProvider(dataProvider, nil)
    }
}
