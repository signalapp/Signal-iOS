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
        deleteFile(filePath, ignoreIfMissing: false)
    }

    class func deleteFileIfExists(_ filePath: String) -> Bool {
        return deleteFile(filePath, ignoreIfMissing: true)
    }

    class func deleteFile(url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    class func deleteFileIfExists(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try deleteFile(url: url)
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

// MARK: -

public extension OWSFileSystem {
    class func deleteFile(_ filePath: String, ignoreIfMissing: Bool = false) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch {
            let nsError = error as NSError

            let isPosixNoSuchFileError = (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT)
            let isCocoaNoSuchFileError = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError)
            if ignoreIfMissing,
                isPosixNoSuchFileError || isCocoaNoSuchFileError {
                // Ignore "No such file or directory" error.
                return true
            } else {
                owsFailDebug("Error: \(error)")
            }
            return false
        }
    }
}
