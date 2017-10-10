//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC

// Stills should be loaded before full GIFs.
enum GiphyRequestPriority {
    case low, high
}

// Represents a request to download a GIF.
//
// Should be cancelled if no longer necessary.
@objc class GiphyAssetRequest: NSObject {
    static let TAG = "[GiphyAssetRequest]"

    let rendition: GiphyRendition
    let priority: GiphyRequestPriority
    // Exactly one of success or failure should be called once,
    // on the main thread _unless_ this request is cancelled before
    // the request succeeds or fails.
    private var success: ((GiphyAssetRequest?, GiphyAsset) -> Void)?
    private var failure: ((GiphyAssetRequest) -> Void)?

    var wasCancelled = false
    // This property is an internal implementation detail of the download process.
    var assetFilePath: String?

    init(rendition: GiphyRendition,
         priority: GiphyRequestPriority,
         success:@escaping ((GiphyAssetRequest?, GiphyAsset) -> Void),
         failure:@escaping ((GiphyAssetRequest) -> Void)
        ) {
        self.rendition = rendition
        self.priority = priority
        self.success = success
        self.failure = failure
    }

    public func cancel() {
        AssertIsOnMainThread()

        wasCancelled = true

        // Don't call the callbacks if the request is cancelled.
        clearCallbacks()
    }

    private func clearCallbacks() {
        AssertIsOnMainThread()

        success = nil
        failure = nil
    }

    public func requestDidSucceed(asset: GiphyAsset) {
        AssertIsOnMainThread()

        success?(self, asset)

        // Only one of the callbacks should be called, and only once.
        clearCallbacks()
    }

    public func requestDidFail() {
        AssertIsOnMainThread()

        failure?(self)

        // Only one of the callbacks should be called, and only once.
        clearCallbacks()
    }
}

// Represents a downloaded gif asset.
//
// The blob on disk is cleaned up when this instance is deallocated,
// so consumers of this resource should retain a strong reference to
// this instance as long as they are using the asset.
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
        // Clean up on the asset on disk.
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

// A simple LRU cache bounded by the number of entries.
//
// TODO: We might want to observe memory pressure notifications.
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

private var URLSessionTaskGiphyAssetRequest: UInt8 = 0

// This extension is used to punch an asset request onto a download task.
extension URLSessionTask {
    var assetRequest: GiphyAssetRequest {
        get {
            return objc_getAssociatedObject(self, &URLSessionTaskGiphyAssetRequest) as! GiphyAssetRequest
        }
        set {
            objc_setAssociatedObject(self, &URLSessionTaskGiphyAssetRequest, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

@objc class GiphyDownloader: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {

    // MARK: - Properties

    static let TAG = "[GiphyDownloader]"

    static let sharedInstance = GiphyDownloader()

    // A private queue used for download task callbacks.
    private let operationQueue = OperationQueue()

    // Force usage as a singleton
    override private init() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let kGiphyBaseURL = "https://api.giphy.com/"

    private func giphyDownloadSession() -> URLSession? {
        // TODO: We need to verify that this session configuration properly
        //       proxies all requests.
        let configuration = URLSessionConfiguration.ephemeral
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

    // 100 entries of which at least half will probably be stills.
    // Actual animated GIFs will usually be less than 3 MB so the
    // max size of the cache on disk should be ~150 MB.  Bear in mind
    // that assets are not always deleted on disk as soon as they are
    // evacuated from the cache; if a cache consumer (e.g. view) is
    // still using the asset, the asset won't be deleted on disk until
    // it is no longer in use.
    private var assetMap = LRUCache<NSURL, GiphyAsset>(maxSize:100)
    // TODO: We could use a proper queue, e.g. implemented with a linked
    // list.
    private var assetRequestQueue = [GiphyAssetRequest]()
    private let kMaxAssetRequestCount = 3
    private var activeAssetRequests = Set<GiphyAssetRequest>()

    // The success and failure callbacks are always called on main queue.
    //
    // The success callbacks may be called synchronously on cache hit, in 
    // which case the GiphyAssetRequest parameter will be nil.
    public func requestAsset(rendition: GiphyRendition,
                             priority: GiphyRequestPriority,
                             success:@escaping ((GiphyAssetRequest?, GiphyAsset) -> Void),
                             failure:@escaping ((GiphyAssetRequest) -> Void)) -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        if let asset = assetMap.get(key:rendition.url) {
            // Synchronous cache hit.
            success(nil, asset)
            return nil
        }

        // Cache miss.
        //
        // Asset requests are done queued and performed asynchronously.
        let assetRequest = GiphyAssetRequest(rendition:rendition,
                                             priority:priority,
                                             success:success,
                                             failure:failure)
        assetRequestQueue.append(assetRequest)
        startRequestIfNecessary()
        return assetRequest
    }

    private func assetRequestDidSucceed(assetRequest: GiphyAssetRequest, asset: GiphyAsset) {
        DispatchQueue.main.async {
            self.assetMap.set(key:assetRequest.rendition.url, value:asset)
            self.activeAssetRequests.remove(assetRequest)
            assetRequest.requestDidSucceed(asset:asset)
            self.startRequestIfNecessary()
        }
    }

    private func assetRequestDidFail(assetRequest: GiphyAssetRequest) {
        DispatchQueue.main.async {
            self.activeAssetRequests.remove(assetRequest)
            assetRequest.requestDidFail()
            self.startRequestIfNecessary()
        }
    }

    private func startRequestIfNecessary() {
        AssertIsOnMainThread()

        DispatchQueue.main.async {
            guard self.activeAssetRequests.count < self.kMaxAssetRequestCount else {
                return
            }
            guard let assetRequest = self.popNextAssetRequest() else {
                return
            }
            guard !assetRequest.wasCancelled else {
                // Discard the cancelled asset request and try again.
                self.startRequestIfNecessary()
                return
            }
            guard UIApplication.shared.applicationState == .active else {
                // If app is not active, fail the asset request.
                self.assetRequestDidFail(assetRequest:assetRequest)
                self.startRequestIfNecessary()
                return
            }

            self.activeAssetRequests.insert(assetRequest)

            if let asset = self.assetMap.get(key:assetRequest.rendition.url) {
                // Deferred cache hit, avoids re-downloading assets that were
                // downloaded while this request was queued.

                self.assetRequestDidSucceed(assetRequest : assetRequest, asset: asset)
                return
            }

            guard let downloadSession = self.giphyDownloadSession() else {
                owsFail("\(GiphyDownloader.TAG) Couldn't create session manager.")
                self.assetRequestDidFail(assetRequest:assetRequest)
                return
            }

            // Start a download task.
            let task = downloadSession.downloadTask(with:assetRequest.rendition.url as URL)
            task.assetRequest = assetRequest
            task.resume()
        }
    }

    private func popNextAssetRequest() -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        var activeAssetRequestURLs = Set<NSURL>()
        for assetRequest in activeAssetRequests {
            activeAssetRequestURLs.insert(assetRequest.rendition.url)
        }

        // Prefer the first "high" priority request;
        // fall back to the first "low" priority request.
        for priority in [GiphyRequestPriority.high, GiphyRequestPriority.low] {
            for (assetRequestIndex, assetRequest) in assetRequestQueue.enumerated() where assetRequest.priority == priority {
                guard !activeAssetRequestURLs.contains(assetRequest.rendition.url) else {
                    // Defer requests if there is already an active asset request with the same URL.
                    continue
                }
                assetRequestQueue.remove(at:assetRequestIndex)
                return assetRequest
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
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
        if let error = error {
            Logger.error("\(GiphyDownloader.TAG) download failed with error: \(error)")
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse else {
            Logger.error("\(GiphyDownloader.TAG) missing or unexpected response: \(task.response)")
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            Logger.error("\(GiphyDownloader.TAG) response has invalid status code: \(statusCode)")
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
        guard let assetFilePath = assetRequest.assetFilePath else {
            Logger.error("\(GiphyDownloader.TAG) task is missing asset file")
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
        let asset = GiphyAsset(rendition: assetRequest.rendition, filePath : assetFilePath)
        assetRequestDidSucceed(assetRequest : assetRequest, asset: asset)
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }

        // We write assets to the temporary directory so that iOS can clean them up.
        // We try to eagerly clean up these assets when they are no longer in use.
        let dirPath = NSTemporaryDirectory()
        let fileExtension = assetRequest.rendition.fileExtension
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
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            assetRequestDidFail(assetRequest:assetRequest)
            return
        }
    }
}
