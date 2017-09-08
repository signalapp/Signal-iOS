//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol DataSource {
    // This method should not be called unless necessary as it
    // be expensive.
    func data() -> Data

    func dataUrl(fileExtension: String) -> URL?
    func dataPath(fileExtension: String) -> String?
    func dataPathIfOnDisk() -> String?
    func dataLength() -> Int
}

@objc
class DataSourceValue: NSObject, DataSource {
    static let TAG = "[DataSourceValue]"

    private let value: Data

    private var path: String?

    // MARK: Constructor

    internal required init(_ value: Data) {
        self.value = value
        super.init()
    }

    func data() -> Data {
        return value
    }

    func dataUrl(fileExtension: String) -> URL? {
        guard let path = dataPath(fileExtension:fileExtension) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func dataPath(fileExtension: String) -> String? {
        if let path = path {
            return path
        }

        let directory = NSTemporaryDirectory()
        let fileName = NSUUID().uuidString + "." + fileExtension
        let filePath = (directory as NSString).appendingPathComponent(fileName)
        do {
            try value.write(to: URL(fileURLWithPath:filePath))
            path = filePath
        } catch {
            owsFail("\(DataSourceValue.TAG) Could not write data to disk: \(fileExtension)")
        }
        return filePath
    }

    func dataPathIfOnDisk() -> String? {
        if let path = path {
            return path
        }
        return nil
    }

    func dataLength() -> Int {
        return value.count
    }

    class func empty() -> DataSource {
        return DataSourceValue(Data())
    }
}

@objc
class DataSourcePath: NSObject, DataSource {
    static let TAG = "[DataSourcePath]"

    private let path: String

    private var cachedData: Data?

    private var cachedLength: Int?

    // MARK: Constructor

    internal required init(_ path: String) {
        self.path = path
        super.init()
    }

    func data() -> Data {
        if let cachedData = cachedData {
            return cachedData
        }
        Logger.error("\(DataSourcePath.TAG) reading data: \(path)")
        do {
            try cachedData = NSData(contentsOfFile:path) as Data
        } catch {
            owsFail("\(DataSourcePath.TAG) Could not read data from disk: \(path)")
            cachedData = Data()
        }
        return cachedData!
    }

    func dataUrl(fileExtension: String) -> URL? {
        return URL(fileURLWithPath: path)
    }

    func dataPath(fileExtension: String) -> String? {
        return path
    }

    func dataPathIfOnDisk() -> String? {
        return path
    }

    func dataLength() -> Int {
        if let cachedLength = cachedLength {
            return cachedLength
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = fileAttributes[FileAttributeKey.size] as! UInt64
            cachedLength = Int(fileSize)
        } catch {
            owsFail("\(DataSourcePath.TAG) Could not read data length from disk: \(path)")
            cachedLength = 0
        }

        return cachedLength!
    }
}

@objc
class DataSourceUrl: NSObject, DataSource {
    static let TAG = "[DataSourceUrl]"

    private let url: URL

    private var cachedData: Data?

    private var cachedLength: Int?

    // MARK: Constructor

    internal required init(_ url: URL) {
        if !url.isFileURL {
            owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)")
        }
        self.url = url
        super.init()
    }

    func data() -> Data {
        if let cachedData = cachedData {
            return cachedData
        }
        guard url.isFileURL else {
            owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)")
            return Data()
        }
        Logger.error("\(DataSourceUrl.TAG) reading data: \(url)")
        do {
            try cachedData = Data(contentsOf:url)
        } catch {
            owsFail("\(DataSourceUrl.TAG) Could not read data from disk: \(url)")
            cachedData = Data()
        }
        return cachedData!
    }

    func dataUrl(fileExtension: String) -> URL? {
        return url
    }

    func dataPath(fileExtension: String) -> String? {
        guard url.isFileURL else {
            owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)")
            return nil
        }
        return url.path
    }

    func dataPathIfOnDisk() -> String? {
        guard url.isFileURL else {
            owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)")
            return nil
        }
        return url.path
    }

    func dataLength() -> Int {
        if let cachedLength = cachedLength {
            return cachedLength
        }
        guard url.isFileURL else {
            owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)")
            return 0
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as! UInt64
            cachedLength = Int(fileSize)
        } catch {
            owsFail("\(DataSourceUrl.TAG) Could not read data length from disk: \(url)")
            cachedLength = 0
        }

        return cachedLength!
    }
}
