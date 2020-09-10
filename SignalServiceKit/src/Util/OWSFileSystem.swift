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

    @discardableResult
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

    class func moveFile(from fromUrl: URL, to toUrl: URL) throws {
        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            throw OWSAssertionError("Source file does not exist.")
        }
        guard !FileManager.default.fileExists(atPath: toUrl.path) else {
            throw OWSAssertionError("Destination file already exists.")
        }
        try FileManager.default.moveItem(at: fromUrl, to: toUrl)

        // Ensure all files moved have the proper data protection class.
        // On large directories this can take a while, so we dispatch async
        // since we're in the launch path.
        DispatchQueue.global().async {
            self.protectRecursiveContents(atPath: toUrl.path)
        }

        #if TESTABLE_BUILD
        guard !FileManager.default.fileExists(atPath: fromUrl.path) else {
            throw OWSAssertionError("Source file does not exist.")
        }
        guard FileManager.default.fileExists(atPath: toUrl.path) else {
            throw OWSAssertionError("Destination file already exists.")
        }
        #endif
    }

    class func recursiveFilesInDirectory(_ dirPath: String) throws -> [String] {
        owsAssertDebug(dirPath.count > 0)

        do {
            return try FileManager.default.subpathsOfDirectory(atPath: dirPath)
                .map { (dirPath as NSString).appendingPathComponent($0) }
                .filter {
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory)
                    return !isDirectory.boolValue
                }

        } catch {
            let nsError = error as NSError
            let isCocoaNoSuchFileError = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)

            if isCocoaNoSuchFileError {
                return []
            } else {
                throw error
            }
        }
    }

    // MARK: - Temporary Files

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
    @objc
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
