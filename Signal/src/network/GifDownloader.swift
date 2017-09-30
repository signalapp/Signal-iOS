//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC

enum GiphyRequestPriority {
    case low, high
}

@objc class GiphyAssetRequest: NSObject {
    static let TAG = "[GiphyAssetRequest]"

    let rendition: GiphyRendition
    let priority: GiphyRequestPriority
    let success: ((GiphyAsset) -> Void)
    let failure: (() -> Void)
    var wasCancelled = false
    var assetFilePath: String?

    init(rendition: GiphyRendition,
         priority: GiphyRequestPriority,
         success:@escaping ((GiphyAsset) -> Void),
         failure:@escaping (() -> Void)
        ) {
        self.rendition = rendition
        self.priority = priority
        self.success = success
        self.failure = failure
    }

    public func cancel() {
        wasCancelled = true
    }
}

@objc class GiphyAsset: NSObject {
    static let TAG = "[GiphyAsset]"

    let rendition: GiphyRendition
    let filePath: String

    init(rendition: GiphyRendition,
         filePath: String) {
        self.rendition = rendition
        self.filePath = filePath
    }

    deinit {
        let filePathCopy = filePath
        DispatchQueue.global().async {
            do {
                let fileManager = FileManager.default
                try fileManager.removeItem(atPath:filePathCopy)
            } catch let error as NSError {
                owsFail("\(GiphyAsset.TAG) file cleanup failed: \(filePathCopy), \(error)")
            }
        }
    }
}

class LRUCache<KeyType: Hashable & Equatable, ValueType> {

    private var cacheMap = [KeyType: ValueType]()
    private var cacheOrder = [KeyType]()
    private let maxSize: Int

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    public func get(key: KeyType) -> ValueType? {
        guard let value = cacheMap[key] else {
            return nil
        }

        // Update cache order.
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)

        return value
    }

    public func set(key: KeyType, value: ValueType) {
        cacheMap[key] = value

        // Update cache order.
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)

        while cacheOrder.count > maxSize {
            guard let staleKey = cacheOrder.first else {
                owsFail("Cache ordering unexpectedly empty")
                return
            }
            cacheOrder.removeFirst()
            cacheMap.removeValue(forKey:staleKey)
        }
    }
}

private var URLSessionTask_GiphyAssetRequest: UInt8 = 0

extension URLSessionTask {
    var assetRequest: GiphyAssetRequest {
        get {
            return objc_getAssociatedObject(self, &URLSessionTask_GiphyAssetRequest) as! GiphyAssetRequest
        }
        set {
            objc_setAssociatedObject(self, &URLSessionTask_GiphyAssetRequest, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

@objc class GifDownloader: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {

    // MARK: - Properties

    static let TAG = "[GifDownloader]"

    static let sharedInstance = GifDownloader()

    private let operationQueue = OperationQueue()

    // Force usage as a singleton
    override private init() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let kGiphyBaseURL = "https://api.giphy.com/"

    private func giphyDownloadSession() -> URLSession? {
//        guard let baseUrl = NSURL(string:kGiphyBaseURL) else {
//            Logger.error("\(GifDownloader.TAG) Invalid base URL.")
//            return nil
//        }
        // TODO: Is this right?
        let configuration = URLSessionConfiguration.ephemeral
        // TODO: Is this right?
        configuration.connectionProxyDictionary = [
            kCFProxyHostNameKey as String: "giphy-proxy-production.whispersystems.org",
            kCFProxyPortNumberKey as String: "80",
            kCFProxyTypeKey as String: kCFProxyTypeHTTPS
        ]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringCacheData
        let session = URLSession(configuration:configuration, delegate:self, delegateQueue:operationQueue)
        return session
    }

    private var assetMap = LRUCache<NSURL, GiphyAsset>(maxSize:100)
    // TODO: We could use a proper queue.
    private var assetRequestQueue = [GiphyAssetRequest]()
    private var isDownloading = false

    // The success and failure handlers are always called on main queue.
    // The success and failure handlers may be called synchronously on cache hit.
    public func downloadAssetAsync(rendition: GiphyRendition,
                                   priority: GiphyRequestPriority,
                              success:@escaping ((GiphyAsset) -> Void),
                              failure:@escaping (() -> Void)) -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        if let asset = assetMap.get(key:rendition.url) {
            success(asset)
            return nil
        }

        var hasRequestCompleted = false
        let assetRequest = GiphyAssetRequest(rendition:rendition,
                                             priority:priority,
                                             success : { asset in
                                                DispatchQueue.main.async {
                                                    // Ensure we call success or failure exactly once.
                                                    guard !hasRequestCompleted else {
                                                        return
                                                    }
                                                    hasRequestCompleted = true

                                                    self.assetMap.set(key:rendition.url, value:asset)
                                                    self.isDownloading = false
                                                    self.downloadIfNecessary()
                                                    success(asset)
                                                }
        },
                                             failure : {
                                                DispatchQueue.main.async {
                                                    // Ensure we call success or failure exactly once.
                                                    guard !hasRequestCompleted else {
                                                        return
                                                    }
                                                    hasRequestCompleted = true

                                                    self.isDownloading = false
                                                    self.downloadIfNecessary()
                                                    failure()
                                                }
        })
        assetRequestQueue.append(assetRequest)
        downloadIfNecessary()
        return assetRequest
    }

    private func downloadIfNecessary() {
        AssertIsOnMainThread()

        DispatchQueue.main.async {
            guard !self.isDownloading else {
                return
            }
            guard let assetRequest = self.popNextAssetRequest() else {
                return
            }
            guard !assetRequest.wasCancelled else {
                DispatchQueue.main.async {
                    self.downloadIfNecessary()
                }
                return
            }
            self.isDownloading = true

            if let asset = self.assetMap.get(key:assetRequest.rendition.url) {
                // Deferred cache hit, avoids re-downloading assets already in the
                // asset cache.
                assetRequest.success(asset)
                return
            }

            guard let downloadSession = self.giphyDownloadSession() else {
                Logger.error("\(GifDownloader.TAG) Couldn't create session manager.")
                assetRequest.failure()
                return
            }

            let task = downloadSession.downloadTask(with:assetRequest.rendition.url as URL)
            task.assetRequest = assetRequest
            task.resume()
        }
    }

    private func popNextAssetRequest() -> GiphyAssetRequest? {
        AssertIsOnMainThread()

//        var result : GiphyAssetRequest?
        for priority in [GiphyRequestPriority.high, GiphyRequestPriority.low] {
            for (assetRequestIndex, assetRequest) in assetRequestQueue.enumerated() {
                if assetRequest.priority == priority {
                    assetRequestQueue.remove(at:assetRequestIndex)
                    return assetRequest
                }
            }
        }

        return nil
    }

    // MARK: URLSessionDataDelegate

    @nonobjc
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        completionHandler(.allow)
    }

    // MARK: URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let assetRequest = task.assetRequest
        guard !assetRequest.wasCancelled else {
            task.cancel()
            assetRequest.failure()
            return
        }
        if let error = error {
            Logger.error("\(GifDownloader.TAG) download failed with error: \(error)")
            assetRequest.failure()
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse else {
            Logger.error("\(GifDownloader.TAG) missing or unexpected response: \(task.response)")
            assetRequest.failure()
            return
        }
        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            Logger.error("\(GifDownloader.TAG) response has invalid status code: \(statusCode)")
            assetRequest.failure()
            return
        }
        guard let assetFilePath = assetRequest.assetFilePath else {
            Logger.error("\(GifDownloader.TAG) task is missing asset file")
            assetRequest.failure()
            return
        }
//        Logger.verbose("\(GifDownloader.TAG) download succeeded: \(assetRequest.rendition.url)")
        let asset = GiphyAsset(rendition: assetRequest.rendition, filePath : assetFilePath)
        assetRequest.success(asset)
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            assetRequest.failure()
            return
        }

        let dirPath = NSTemporaryDirectory()
        let fileExtension = assetRequest.rendition.fileExtension()
        let fileName = (NSUUID().uuidString as NSString).appendingPathExtension(fileExtension)!
        let filePath = (dirPath as NSString).appendingPathComponent(fileName)

        do {
            try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath:filePath))
            assetRequest.assetFilePath = filePath
        } catch let error as NSError {
            owsFail("\(GiphyAsset.TAG) file move failed from: \(location), to: \(filePath), \(error)")
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            assetRequest.failure()
            return
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            assetRequest.failure()
            return
        }
    }
}
