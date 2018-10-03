//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC
import SignalServiceKit
import SignalMessaging

// Stills should be loaded before full GIFs.
enum GiphyRequestPriority {
    case low, high
}

enum GiphyAssetSegmentState: UInt {
    case waiting
    case downloading
    case complete
    case failed
}

class GiphyAssetSegment: NSObject {

    public let index: UInt
    public let segmentStart: UInt
    public let segmentLength: UInt
    // The amount of the segment that is overlap.  
    // The overlap lies in the _first_ n bytes of the segment data.
    public let redundantLength: UInt

    // This state should only be accessed on the main thread.
    public var state: GiphyAssetSegmentState = .waiting {
        didSet {
            AssertIsOnMainThread()
        }
    }

    // This state is accessed off the main thread.
    //
    // * During downloads it will be accessed on the task delegate queue.
    // * After downloads it will be accessed on a worker queue. 
    private var segmentData = Data()

    // This state should only be accessed on the main thread.
    public weak var task: URLSessionDataTask?

    init(index: UInt,
         segmentStart: UInt,
         segmentLength: UInt,
         redundantLength: UInt) {
        self.index = index
        self.segmentStart = segmentStart
        self.segmentLength = segmentLength
        self.redundantLength = redundantLength
    }

    public func totalDataSize() -> UInt {
        return UInt(segmentData.count)
    }

    public func append(data: Data) {
        guard state == .downloading else {
            owsFailDebug("appending data in invalid state: \(state)")
            return
        }

        segmentData.append(data)
    }

    public func mergeData(assetData: inout Data) -> Bool {
        guard state == .complete else {
            owsFailDebug("merging data in invalid state: \(state)")
            return false
        }
        guard UInt(segmentData.count) == segmentLength else {
            owsFailDebug("segment data length: \(segmentData.count) doesn't match expected length: \(segmentLength)")
            return false
        }

        // In some cases the last two segments will overlap.
        // In that case, we only want to append the non-overlapping
        // tail of the segment data.
        let bytesToIgnore = Int(redundantLength)
        if bytesToIgnore > 0 {
            let subdata = segmentData.subdata(in: bytesToIgnore..<Int(segmentLength))
            assetData.append(subdata)
        } else {
            assetData.append(segmentData)
        }
        return true
    }
}

enum GiphyAssetRequestState: UInt {
    // Does not yet have content length.
    case waiting
    // Getting content length.
    case requestingSize
    // Has content length, ready for downloads or downloads in flight.
    case active
    // Success
    case complete
    // Failure
    case failed
}

// Represents a request to download a GIF.
//
// Should be cancelled if no longer necessary.
@objc class GiphyAssetRequest: NSObject {

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

    // This state should only be accessed on the main thread.
    private var segments = [GiphyAssetSegment]()
    public var state: GiphyAssetRequestState = .waiting
    public var contentLength: Int = 0 {
        didSet {
            AssertIsOnMainThread()
            assert(oldValue == 0)
            assert(contentLength > 0)

            createSegments()
        }
    }
    public weak var contentLengthTask: URLSessionDataTask?

    init(rendition: GiphyRendition,
         priority: GiphyRequestPriority,
         success:@escaping ((GiphyAssetRequest?, GiphyAsset) -> Void),
         failure:@escaping ((GiphyAssetRequest) -> Void)) {
        self.rendition = rendition
        self.priority = priority
        self.success = success
        self.failure = failure

        super.init()
    }

    private func segmentSize() -> UInt {
        AssertIsOnMainThread()

        let contentLength = UInt(self.contentLength)
        guard contentLength > 0 else {
            owsFailDebug("rendition missing contentLength")
            requestDidFail()
            return 0
        }

        let k1MB: UInt = 1024 * 1024
        let k500KB: UInt = 500 * 1024
        let k100KB: UInt = 100 * 1024
        let k50KB: UInt = 50 * 1024
        let k10KB: UInt = 10 * 1024
        let k1KB: UInt = 1 * 1024
        for segmentSize in [k1MB, k500KB, k100KB, k50KB, k10KB, k1KB ] {
            if contentLength >= segmentSize {
                return segmentSize
            }
        }
        return contentLength
    }

    private func createSegments() {
        AssertIsOnMainThread()

        let segmentLength = segmentSize()
        guard segmentLength > 0 else {
            return
        }
        let contentLength = UInt(self.contentLength)

        var nextSegmentStart: UInt = 0
        var index: UInt = 0
        while nextSegmentStart < contentLength {
            var segmentStart: UInt = nextSegmentStart
            var redundantLength: UInt = 0
            // The last segment may overlap the penultimate segment
            // in order to keep the segment sizes uniform.
            if segmentStart + segmentLength > contentLength {
                redundantLength = segmentStart + segmentLength - contentLength
                segmentStart = contentLength - segmentLength
            }
            let assetSegment = GiphyAssetSegment(index: index,
                                                 segmentStart: segmentStart,
                                                 segmentLength: segmentLength,
                                                 redundantLength: redundantLength)
            segments.append(assetSegment)
            nextSegmentStart = segmentStart + segmentLength
            index += 1
        }
    }

    private func firstSegmentWithState(state: GiphyAssetSegmentState) -> GiphyAssetSegment? {
        AssertIsOnMainThread()

        for segment in segments {
            guard segment.state != .failed else {
                owsFailDebug("unexpected failed segment.")
                continue
            }
            if segment.state == state {
                return segment
            }
        }
        return nil
    }

    public func firstWaitingSegment() -> GiphyAssetSegment? {
        AssertIsOnMainThread()

        return firstSegmentWithState(state: .waiting)
    }

    public func downloadingSegmentsCount() -> UInt {
        AssertIsOnMainThread()

        var result: UInt = 0
        for segment in segments {
            guard segment.state != .failed else {
                owsFailDebug("unexpected failed segment.")
                continue
            }
            if segment.state == .downloading {
                result += 1
            }
        }
        return result
    }

    public func areAllSegmentsComplete() -> Bool {
        AssertIsOnMainThread()

        for segment in segments {
            guard segment.state == .complete else {
                return false
            }
        }
        return true
    }

    public func writeAssetToFile(gifFolderPath: String) -> GiphyAsset? {

        var assetData = Data()
        for segment in segments {
            guard segment.state == .complete else {
                owsFailDebug("unexpected incomplete segment.")
                return nil
            }
            guard segment.totalDataSize() > 0 else {
                owsFailDebug("could not merge empty segment.")
                return nil
            }
            guard segment.mergeData(assetData: &assetData) else {
                owsFailDebug("failed to merge segment data.")
                return nil
            }
        }

        guard assetData.count == contentLength else {
            owsFailDebug("asset data has unexpected length.")
            return nil
        }

        guard assetData.count > 0 else {
            owsFailDebug("could not write empty asset to disk.")
            return nil
        }

        let fileExtension = rendition.fileExtension
        let fileName = (NSUUID().uuidString as NSString).appendingPathExtension(fileExtension)!
        let filePath = (gifFolderPath as NSString).appendingPathComponent(fileName)

        Logger.verbose("filePath: \(filePath).")

        do {
            try assetData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
            let asset = GiphyAsset(rendition: rendition, filePath: filePath)
            return asset
        } catch let error as NSError {
            owsFailDebug("file write failed: \(filePath), \(error)")
            return nil
        }
    }

    public func cancel() {
        AssertIsOnMainThread()

        wasCancelled = true
        contentLengthTask?.cancel()
        contentLengthTask = nil
        for segment in segments {
            segment.task?.cancel()
            segment.task = nil
        }

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
                try fileManager.removeItem(atPath: filePathCopy)
            } catch let error as NSError {
                owsFailDebug("file cleanup failed: \(filePathCopy), \(error)")
            }
        }
    }
}

private var URLSessionTaskGiphyAssetRequest: UInt8 = 0
private var URLSessionTaskGiphyAssetSegment: UInt8 = 0

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
    var assetSegment: GiphyAssetSegment {
        get {
            return objc_getAssociatedObject(self, &URLSessionTaskGiphyAssetSegment) as! GiphyAssetSegment
        }
        set {
            objc_setAssociatedObject(self, &URLSessionTaskGiphyAssetSegment, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

@objc class GiphyDownloader: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {

    // MARK: - Properties

    static let sharedInstance = GiphyDownloader()

    var gifFolderPath = ""

    // Force usage as a singleton
    override private init() {
        AssertIsOnMainThread()

        super.init()

        SwiftSingletons.register(self)

        ensureGifFolder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let kGiphyBaseURL = "https://api.giphy.com/"

    private lazy var giphyDownloadSession: URLSession = {
        AssertIsOnMainThread()

        let configuration = GiphyAPI.giphySessionConfiguration()
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringCacheData
        configuration.httpMaximumConnectionsPerHost = 10
        let session = URLSession(configuration: configuration,
                                 delegate: self,
                                 delegateQueue: nil)
        return session
    }()

    // 100 entries of which at least half will probably be stills.
    // Actual animated GIFs will usually be less than 3 MB so the
    // max size of the cache on disk should be ~150 MB.  Bear in mind
    // that assets are not always deleted on disk as soon as they are
    // evacuated from the cache; if a cache consumer (e.g. view) is
    // still using the asset, the asset won't be deleted on disk until
    // it is no longer in use.
    private var assetMap = LRUCache<NSURL, GiphyAsset>(maxSize: 100)
    // TODO: We could use a proper queue, e.g. implemented with a linked
    // list.
    private var assetRequestQueue = [GiphyAssetRequest]()

    // The success and failure callbacks are always called on main queue.
    //
    // The success callbacks may be called synchronously on cache hit, in
    // which case the GiphyAssetRequest parameter will be nil.
    public func requestAsset(rendition: GiphyRendition,
                             priority: GiphyRequestPriority,
                             success:@escaping ((GiphyAssetRequest?, GiphyAsset) -> Void),
                             failure:@escaping ((GiphyAssetRequest) -> Void)) -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        if let asset = assetMap.get(key: rendition.url) {
            // Synchronous cache hit.
            Logger.verbose("asset cache hit: \(rendition.url)")
            success(nil, asset)
            return nil
        }

        // Cache miss.
        //
        // Asset requests are done queued and performed asynchronously.
        Logger.verbose("asset cache miss: \(rendition.url)")
        let assetRequest = GiphyAssetRequest(rendition: rendition,
                                             priority: priority,
                                             success: success,
                                             failure: failure)
        assetRequestQueue.append(assetRequest)
        // Process the queue (which may start this request)
        // asynchronously so that the caller has time to store
        // a reference to the asset request returned by this
        // method before its success/failure handler is called.
        processRequestQueueAsync()
        return assetRequest
    }

    public func cancelAllRequests() {
        AssertIsOnMainThread()

        Logger.verbose("cancelAllRequests")

        self.assetRequestQueue.forEach { $0.cancel() }
        self.assetRequestQueue = []
    }

    private func segmentRequestDidSucceed(assetRequest: GiphyAssetRequest, assetSegment: GiphyAssetSegment) {
        DispatchQueue.main.async {
            assetSegment.state = .complete

            if assetRequest.areAllSegmentsComplete() {
                // If the asset request has completed all of its segments,
                // try to write the asset to file.
                assetRequest.state = .complete

                // Move write off main thread.
                DispatchQueue.global().async {
                    guard let asset = assetRequest.writeAssetToFile(gifFolderPath: self.gifFolderPath) else {
                        self.segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
                        return
                    }
                    self.assetRequestDidSucceed(assetRequest: assetRequest, asset: asset)
                }
            } else {
                self.processRequestQueueSync()
            }
        }
    }

    private func assetRequestDidSucceed(assetRequest: GiphyAssetRequest, asset: GiphyAsset) {

        DispatchQueue.main.async {
            self.assetMap.set(key: assetRequest.rendition.url, value: asset)
            self.removeAssetRequestFromQueue(assetRequest: assetRequest)
            assetRequest.requestDidSucceed(asset: asset)
        }
    }

    // TODO: If we wanted to implement segment retry, we'll need to add
    //       a segmentRequestDidFail() method.
    private func segmentRequestDidFail(assetRequest: GiphyAssetRequest, assetSegment: GiphyAssetSegment) {
        DispatchQueue.main.async {
            assetSegment.state = .failed
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
        }
    }

    private func assetRequestDidFail(assetRequest: GiphyAssetRequest) {

        DispatchQueue.main.async {
            self.removeAssetRequestFromQueue(assetRequest: assetRequest)
            assetRequest.requestDidFail()
        }
    }

    private func removeAssetRequestFromQueue(assetRequest: GiphyAssetRequest) {
        AssertIsOnMainThread()

        guard assetRequestQueue.contains(assetRequest) else {
            Logger.warn("could not remove asset request from queue: \(assetRequest.rendition.url)")
            return
        }

        assetRequestQueue = assetRequestQueue.filter { $0 != assetRequest }
        // Process the queue async to ensure that state in the downloader
        // classes is consistent before we try to start a new request.
        processRequestQueueAsync()
    }

    private func processRequestQueueAsync() {
        DispatchQueue.main.async {
            self.processRequestQueueSync()
        }
    }

    // * Start a segment request or content length request if possible.
    // * Complete/cancel asset requests if possible.
    //
    private func processRequestQueueSync() {
        AssertIsOnMainThread()

        guard let assetRequest = popNextAssetRequest() else {
            return
        }
        guard !assetRequest.wasCancelled else {
            // Discard the cancelled asset request and try again.
            removeAssetRequestFromQueue(assetRequest: assetRequest)
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            // If app is not active, fail the asset request.
            assetRequest.state = .failed
            assetRequestDidFail(assetRequest: assetRequest)
            processRequestQueueSync()
            return
        }

        if let asset = assetMap.get(key: assetRequest.rendition.url) {
            // Deferred cache hit, avoids re-downloading assets that were
            // downloaded while this request was queued.

            assetRequest.state = .complete
            assetRequestDidSucceed(assetRequest: assetRequest, asset: asset)
            return
        }

        if assetRequest.state == .waiting {
            // If asset request hasn't yet determined the resource size,
            // try to do so now.
            assetRequest.state = .requestingSize

            var request = URLRequest(url: assetRequest.rendition.url as URL)
            request.httpMethod = "HEAD"
            request.httpShouldUsePipelining = true

            let task = giphyDownloadSession.dataTask(with: request, completionHandler: { data, response, error -> Void in
                if let data = data, data.count > 0 {
                    owsFailDebug("HEAD request has unexpected body: \(data.count).")
                }
                self.handleAssetSizeResponse(assetRequest: assetRequest, response: response, error: error)
            })
            assetRequest.contentLengthTask = task
            task.resume()
        } else {
            // Start a download task.

            guard let assetSegment = assetRequest.firstWaitingSegment() else {
                owsFailDebug("queued asset request does not have a waiting segment.")
                return
            }
            assetSegment.state = .downloading

            var request = URLRequest(url: assetRequest.rendition.url as URL)
            request.httpShouldUsePipelining = true
            let rangeHeaderValue = "bytes=\(assetSegment.segmentStart)-\(assetSegment.segmentStart + assetSegment.segmentLength - 1)"
            request.addValue(rangeHeaderValue, forHTTPHeaderField: "Range")
            let task: URLSessionDataTask = giphyDownloadSession.dataTask(with: request)
            task.assetRequest = assetRequest
            task.assetSegment = assetSegment
            assetSegment.task = task
            task.resume()
        }

        // Recurse; we may be able to start multiple downloads.
        processRequestQueueSync()
    }

    private func handleAssetSizeResponse(assetRequest: GiphyAssetRequest, response: URLResponse?, error: Error?) {
        guard error == nil else {
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            owsFailDebug("Asset size response is invalid.")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        guard let contentLengthString = httpResponse.allHeaderFields["Content-Length"] as? String else {
            owsFailDebug("Asset size response is missing content length.")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        guard let contentLength = Int(contentLengthString) else {
            owsFailDebug("Asset size response has unparsable content length.")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        guard contentLength > 0 else {
            owsFailDebug("Asset size response has invalid content length.")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }

        DispatchQueue.main.async {
            assetRequest.contentLength = contentLength
            assetRequest.state = .active
            self.processRequestQueueSync()
        }
    }

    // Return the first asset request for which we either:
    //
    // * Need to download the content length.
    // * Need to download at least one of its segments.
    private func popNextAssetRequest() -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        let kMaxAssetRequestCount: UInt = 3
        let kMaxAssetRequestsPerAssetCount: UInt = kMaxAssetRequestCount - 1

        // Prefer the first "high" priority request;
        // fall back to the first "low" priority request.
        var activeAssetRequestsCount: UInt = 0
        for priority in [GiphyRequestPriority.high, GiphyRequestPriority.low] {
            for assetRequest in assetRequestQueue where assetRequest.priority == priority {
                switch assetRequest.state {
                case .waiting:
                    // This asset request needs its content length.
                    return assetRequest
                case .requestingSize:
                    activeAssetRequestsCount += 1
                    // Ensure that only N requests are active at a time.
                    guard activeAssetRequestsCount < kMaxAssetRequestCount else {
                        return nil
                    }
                    continue
                case .active:
                    break
                case .complete:
                    continue
                case .failed:
                    continue
                }

                let downloadingSegmentsCount = assetRequest.downloadingSegmentsCount()
                activeAssetRequestsCount += downloadingSegmentsCount
                // Ensure that only N segment requests are active per asset at a time.
                guard downloadingSegmentsCount < kMaxAssetRequestsPerAssetCount else {
                    continue
                }
                // Ensure that only N requests are active at a time.
                guard activeAssetRequestsCount < kMaxAssetRequestCount else {
                    return nil
                }
                guard assetRequest.firstWaitingSegment() != nil else {
                    /// Asset request does not have a waiting segment.
                    continue
                }
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

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let assetRequest = dataTask.assetRequest
        let assetSegment = dataTask.assetSegment
        guard !assetRequest.wasCancelled else {
            dataTask.cancel()
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }
        assetSegment.append(data: data)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }

    // MARK: URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        let assetRequest = task.assetRequest
        let assetSegment = task.assetSegment
        guard !assetRequest.wasCancelled else {
            task.cancel()
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }
        if let error = error {
            Logger.error("download failed with error: \(error)")
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse else {
            Logger.error("missing or unexpected response: \(String(describing: task.response))")
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }
        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            Logger.error("response has invalid status code: \(statusCode)")
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }
        guard assetSegment.totalDataSize() == assetSegment.segmentLength else {
            Logger.error("segment is missing data: \(statusCode)")
            segmentRequestDidFail(assetRequest: assetRequest, assetSegment: assetSegment)
            return
        }

        segmentRequestDidSucceed(assetRequest: assetRequest, assetSegment: assetSegment)
    }

    // MARK: Temp Directory

    public func ensureGifFolder() {
        // We write assets to the temporary directory so that iOS can clean them up.
        // We try to eagerly clean up these assets when they are no longer in use.

        let tempDirPath = OWSTemporaryDirectory()
        let dirPath = (tempDirPath as NSString).appendingPathComponent("GIFs")
        do {
            let fileManager = FileManager.default

            // Try to delete existing folder if necessary.
            if fileManager.fileExists(atPath: dirPath) {
                try fileManager.removeItem(atPath: dirPath)
                gifFolderPath = dirPath
            }
            // Try to create folder if necessary.
            if !fileManager.fileExists(atPath: dirPath) {
                try fileManager.createDirectory(atPath: dirPath,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
                gifFolderPath = dirPath
            }

            // Don't back up Giphy downloads.
            OWSFileSystem.protectFileOrFolder(atPath: dirPath)
        } catch let error as NSError {
            owsFailDebug("ensureTempFolder failed: \(dirPath), \(error)")
            gifFolderPath = tempDirPath
        }
    }
}
