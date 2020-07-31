//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSFileSystem {
    class func temporaryFileUrl(fileExtension: String? = nil,
                                isAvailableWhileDeviceLocked: Bool = false) -> URL {
        return URL(fileURLWithPath: temporaryFilePath(fileExtension: fileExtension,
                                                      isAvailableWhileDeviceLocked: isAvailableWhileDeviceLocked))
    }

    class func temporaryFilePath(fileExtension: String? = nil) -> String {
        temporaryFilePath(fileExtension: fileExtension, isAvailableWhileDeviceLocked: false)
    }

    class func temporaryFilePath(fileExtension: String? = nil,
                                 isAvailableWhileDeviceLocked: Bool = false) -> String {

        let tempDirPath = (isAvailableWhileDeviceLocked
            ? OWSTemporaryDirectoryAccessibleAfterFirstAuth()
            : OWSTemporaryDirectory())
        var fileName = UUID().uuidString
        if let fileExtension = fileExtension,
            !fileExtension.isEmpty {
            fileName = String(format: "\(fileName).\(fileExtension)")
        }
        let filePath = (tempDirPath as NSString).appendingPathComponent(fileName)
        return filePath
    }
}
