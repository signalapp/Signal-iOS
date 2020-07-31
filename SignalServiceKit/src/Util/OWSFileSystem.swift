//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSFileSystem {
    class func fileOrFolderExists(atPath filePath: String) -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    class func fileOrFolderExists(url: URL) -> Bool {
        fileOrFolderExists(atPath: url.path)
    }

    class func deleteFile(_ filePath: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    class func deleteFileIfExists(_ filePath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return true
        }
        return deleteFile(filePath)
    }

    class func deleteFile(url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

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
