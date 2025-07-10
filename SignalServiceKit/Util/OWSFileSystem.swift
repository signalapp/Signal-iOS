//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let owsTempDir = {
    let dirPath = NSTemporaryDirectory().appendingPathComponent("ows_temp_\(UUID())")
    owsPrecondition(OWSFileSystem.ensureDirectoryExists(dirPath, fileProtectionType: .complete))
    return dirPath
}()
/// Use instead of NSTemporaryDirectory()
/// prefer the more restrictice OWSTemporaryDirectory,
/// unless the temp data may need to be accessed while the device is locked.
public func OWSTemporaryDirectory() -> String {
    return owsTempDir
}

public func OWSTemporaryDirectoryAccessibleAfterFirstAuth() -> String {
    let dirPath = NSTemporaryDirectory()
    owsPrecondition(OWSFileSystem.ensureDirectoryExists(dirPath, fileProtectionType: .completeUntilFirstUserAuthentication))
    return dirPath
}

private let cleanTmpDispatchQueue = DispatchQueue(label: "org.signal.clean-tmp", qos: .utility)
/// > NOTE: We need to call this method on launch _and_ every time the app becomes active,
/// >       since file protection may prevent it from succeeding in the background.
public func ClearOldTemporaryDirectories() {
    let dispatchTime = DispatchTime.now() + .seconds(3)
    cleanTmpDispatchQueue.asyncAfter(deadline: dispatchTime, execute: DispatchWorkItem(block: {
        ClearOldTemporaryDirectoriesSync()
    }))
}

private func ClearOldTemporaryDirectoriesSync() {
    // Ignore the "current" temp directory.
    let currentTempDirName = (OWSTemporaryDirectory() as NSString).lastPathComponent

    let thresholdDate = CurrentAppContext().appLaunchTime
    let dirPath = NSTemporaryDirectory()
    let fileNames: [String]
    do {
        fileNames = try FileManager.default.contentsOfDirectory(atPath: dirPath)
    } catch {
        owsFailDebug("contentsOfDirectoryAtPath error: \(error)")
        return
    }
    for fileName in fileNames {
        if fileName == currentTempDirName {
            continue
        }

        let filePath = dirPath.appendingPathComponent(fileName)

        // Delete files with either:
        //
        // a) "ows_temp" name prefix.
        // b) modified time before app launch time.
        if !fileName.hasPrefix("ows_temp") {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                // Don't delete files which were created in the last N minutes.
                let mtime = attributes[.modificationDate] as? Date
                guard let mtime else {
                    Logger.error("failed to get a modification date for file or directory at: \(filePath)")
                    continue
                }
                if mtime > thresholdDate {
                    continue
                }
            } catch {
                // This is fine; the file may have been deleted since we found it.
                Logger.error("Could not get attributes of file or directory at: \(filePath)")
                continue
            }
        }

        if !OWSFileSystem.deleteFileIfExists(filePath) {
            // This can happen if the app launches before the phone is unlocked.
            // Clean up will occur when app becomes active.
            Logger.warn("Could not delete old temp directory: \(filePath)")
        }
    }
}

public enum OWSFileSystem {

    @discardableResult
    private static func protectRecursiveContents(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        if !isDirectory.boolValue {
            return Self.protectFileOrFolder(atPath: path)
        }
        let dirPath = path
        guard let directoryEnumerator = FileManager.default.enumerator(atPath: dirPath) else {
            return true
        }

        var success = true
        for relativePath in directoryEnumerator {
            guard let relativePath = relativePath as? String else {
                owsFail("type of elements from FileManager.enumerator was not String")
            }
            let filePath = dirPath.appendingPathComponent(relativePath)
            success = Self.protectFileOrFolder(atPath: filePath) && success
        }
        return success
    }

    @discardableResult
    public static func protectFileOrFolder(atPath path: String, fileProtectionType: FileProtectionType = .completeUntilFirstUserAuthentication) -> Bool {
        do {
            try FileManager.default.setAttributes([.protectionKey: fileProtectionType], ofItemAtPath: path)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return false
        } catch {
            owsFailDebug("Could not protect file or folder: \(error)")
            return false
        }

        var resourceAttrs = URLResourceValues()
        resourceAttrs.isExcludedFromBackup = true
        var resourceUrl = URL(fileURLWithPath: path)
        do {
            try resourceUrl.setResourceValues(resourceAttrs)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return false
        } catch {
            owsFailDebug("Could not protect file or folder: \(error)")
            return false
        }

        return true
    }

    public static func appLibraryDirectoryPath() -> String {
        guard let last = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).last else {
            owsFail("no urls returned for the user library directory")
        }
        return last.path
    }

    public static func appDocumentDirectoryPath() -> String {
        CurrentAppContext().appDocumentDirectoryPath()
    }

    public static func appSharedDataDirectoryURL() -> URL {
        URL(fileURLWithPath: Self.appSharedDataDirectoryPath())
    }

    public static func appSharedDataDirectoryPath() -> String {
        CurrentAppContext().appSharedDataDirectoryPath()
    }

    private static let cachesDirectoryPathPrecomputed: String = {
        guard let result = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            owsFail("no search paths returned for user caches directories")
        }
        return result
    }()
    public static func cachesDirectoryPath() -> String {
        return cachesDirectoryPathPrecomputed
    }

    public static func moveFilePath(_ oldFilePath: String, toFilePath newFilePath: String) throws {
        try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)

        // Ensure all files moved have the proper data protection class.
        // On large directories this can take a while, so we dispatch async
        // since we're in the launch path.
        DispatchQueue.global().async {
            _ = Self.protectRecursiveContents(atPath: newFilePath)
        }
    }

    public static func ensureFileExists(_ filePath: String) -> Bool {
        if FileManager.default.fileExists(atPath: filePath) || FileManager.default.createFile(atPath: filePath, contents: nil){
            return Self.protectFileOrFolder(atPath: filePath)
        }

        owsFailDebug("Failed to create file.")
        return false
    }

    public static func deleteContents(ofDirectory dirPath: String) {
        do {
            let filePaths = try Self.recursiveFilesInDirectory(dirPath)
            for filePath in filePaths {
                Self.deleteFileIfExists(filePath)
            }
        } catch {
            owsFailDebug("Could not retrieve files in directory.")
        }
    }

    public static func fileSize(ofPath filePath: String) -> NSNumber? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
            guard let result = attrs[.size] as? NSNumber else {
                owsFail("file size attribute was not NSNumber")
            }
            return result
        } catch {
            Logger.error("Couldn't fetch file size: \(error)")
            return nil
        }
    }

    public static func fileSize(of fileUrl: URL) -> NSNumber? {
        Self.fileSize(ofPath: fileUrl.path)
    }

    public static func folderSizeRecursive(ofPath dirPath: String) -> NSNumber? {
        do {
            let filePaths = try Self.recursiveFilesInDirectory(dirPath)
            var sum: UInt64 = 0
            for filePath in filePaths {
                guard let fileSize = fileSize(ofPath: filePath) else { return nil }
                sum += fileSize.uint64Value
            }
            return NSNumber(value: sum)
        } catch {
            Logger.error("Couldn't fetch file sizes \(error)")
            return nil
        }
    }

    public static func folderSizeRecursive(of dirUrl: URL) -> NSNumber? {
        return self.folderSizeRecursive(ofPath: dirUrl.path)
    }
}

extension OWSFileSystem {

    /// - Returns: false iff the directory does not exist and could not be created or setting the file protection type fails
    @discardableResult
    public static func ensureDirectoryExists(_ dirPath: String) -> Bool {
        ensureDirectoryExists(dirPath, fileProtectionType: .completeUntilFirstUserAuthentication)
    }

    fileprivate static func ensureDirectoryExists(_ dirPath: String, fileProtectionType: FileProtectionType) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
            return protectFileOrFolder(atPath: dirPath, fileProtectionType: fileProtectionType)
        } catch {
            owsFailDebug("Failed to create directory: \(dirPath), error: \(error)")
            return false
        }
    }
}

public extension OWSFileSystem {
    static func fileOrFolderExists(atPath filePath: String) -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    static func fileOrFolderExists(url: URL) -> Bool {
        fileOrFolderExists(atPath: url.path)
    }

    static func fileExistsAndIsNotDirectory(atPath filePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    static func fileExistsAndIsNotDirectory(url: URL) -> Bool {
        fileExistsAndIsNotDirectory(atPath: url.path)
    }

    @discardableResult
    static func deleteFile(_ filePath: String) -> Bool {
        deleteFile(filePath, ignoreIfMissing: false)
    }

    @discardableResult
    static func deleteFileIfExists(_ filePath: String) -> Bool {
        return deleteFile(filePath, ignoreIfMissing: true)
    }

    static func deleteFile(url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func deleteFileIfExists(url: URL) throws {
        do {
            try deleteFile(url: url)
        } catch POSIXError.ENOENT, CocoaError.fileNoSuchFile {
            // this is fine
        }
    }

    static func moveFile(from fromUrl: URL, to toUrl: URL) throws {
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

    static func copyFile(from fromUrl: URL, to toUrl: URL) throws {
        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            throw OWSAssertionError("Source file does not exist.")
        }
        guard !FileManager.default.fileExists(atPath: toUrl.path) else {
            throw OWSAssertionError("Destination file already exists.")
        }
        try FileManager.default.copyItem(at: fromUrl, to: toUrl)

        // Ensure all files copied have the proper data protection class.
        // On large directories this can take a while, so we dispatch async
        // since we're in the launch path.
        DispatchQueue.global().async {
            self.protectRecursiveContents(atPath: toUrl.path)
        }

        #if TESTABLE_BUILD
        guard FileManager.default.fileExists(atPath: toUrl.path) else {
            throw OWSAssertionError("Destination file not created.")
        }
        #endif
    }

    static func recursiveFilesInDirectory(_ dirPath: String) throws -> [String] {
        owsAssertDebug(!dirPath.isEmpty)

        do {
            return try FileManager.default.subpathsOfDirectory(atPath: dirPath)
                .map { (dirPath as NSString).appendingPathComponent($0) }
                .filter {
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory)
                    return !isDirectory.boolValue
                }

        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }
}

// MARK: - Temporary Files

public extension OWSFileSystem {

    static func temporaryFileUrl(
        fileExtension: String? = nil,
        isAvailableWhileDeviceLocked: Bool = false
    ) -> URL {
        return URL(fileURLWithPath: temporaryFilePath(
            fileName: nil,
            fileExtension: fileExtension,
            isAvailableWhileDeviceLocked: isAvailableWhileDeviceLocked
        ))
    }

    static func temporaryFileUrl(
        fileName: String,
        fileExtension: String? = nil,
        isAvailableWhileDeviceLocked: Bool = false
    ) -> URL {
        return URL(fileURLWithPath: temporaryFilePath(
            fileName: fileName,
            fileExtension: fileExtension,
            isAvailableWhileDeviceLocked: isAvailableWhileDeviceLocked
        ))
    }

    static func temporaryFilePath(
        fileName: String? = nil,
        fileExtension: String? = nil
    ) -> String {
        temporaryFilePath(
            fileName: fileName,
            fileExtension: fileExtension,
            isAvailableWhileDeviceLocked: false
        )
    }

    static func temporaryFilePath(
        fileName: String? = nil,
        fileExtension: String? = nil,
        isAvailableWhileDeviceLocked: Bool = false
    ) -> String {
        let tempDirPath = tempDirPath(availableWhileDeviceLocked: isAvailableWhileDeviceLocked)
        var fileName = fileName ?? UUID().uuidString
        if let fileExtension = fileExtension,
            !fileExtension.isEmpty {
            fileName = String(format: "\(fileName).\(fileExtension)")
        }
        let filePath = (tempDirPath as NSString).appendingPathComponent(fileName)
        return filePath
    }

    private static func tempDirPath(availableWhileDeviceLocked: Bool) -> String {
        return availableWhileDeviceLocked
            ? OWSTemporaryDirectoryAccessibleAfterFirstAuth()
            : OWSTemporaryDirectory()
    }
}

// MARK: -

public extension OWSFileSystem {
    static func deleteFile(_ filePath: String, ignoreIfMissing: Bool = false) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: filePath)
            return true
        } catch POSIXError.ENOENT where ignoreIfMissing, CocoaError.fileNoSuchFile where ignoreIfMissing {
            // Ignore "No such file or directory" error.
            return true
        } catch CocoaError.fileWriteNoPermission {
            let attemptedUrl = URL(fileURLWithPath: filePath)
            let knownNoWritePermissionUrls = [
                OWSFileSystem.appSharedDataDirectoryURL().appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            ]
            owsAssertDebug(knownNoWritePermissionUrls.contains(attemptedUrl))
            return false
        } catch {
            owsFailDebug("\(error.shortDescription)")
            return false
        }
    }
}

// MARK: - Remaining space

public extension OWSFileSystem {
    /// Get the remaining free space for a path's volume in bytes.
    ///
    /// See [Apple's example][0]. It checks "important" storage (versus "opportunistic" storage).
    ///
    /// [0]: https://developer.apple.com/documentation/foundation/nsurlresourcekey/checking_volume_storage_capacity
    static func freeSpaceInBytes(forPath path: URL) throws -> UInt64 {
        let resourceValues = try path.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let result = resourceValues.volumeAvailableCapacityForImportantUsage else {
            throw OWSGenericError("Could not determine remaining disk space")
        }
        guard result >= 0 else {
            throw OWSGenericError("Got negative remaining disk space!")
        }
        return UInt64(result)
    }
}

// MARK: - Creating Partial files

public extension OWSFileSystem {
    static func createTempFileSlice(url: URL, start: Int) throws -> (URL, Int) {
        // Resuming, slice attachment data in memory.
        let dataSliceFileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)

        // TODO: It'd be better if we could slice on disk.
        let entireFileData = try Data(contentsOf: url)
        let dataSlice = entireFileData.suffix(from: start)
        let dataSliceLength = dataSlice.count
        guard dataSliceLength + start == entireFileData.count else {
            throw OWSAssertionError("Could not slice the data.")
        }

        // Write the slice to a temporary file.
        try dataSlice.write(to: dataSliceFileUrl)

        return (dataSliceFileUrl, dataSliceLength)
    }
}
