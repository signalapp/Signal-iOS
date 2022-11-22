//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import ObjectiveC

// Stills should be loaded before full GIFs.
public enum ProxiedContentRequestPriority {
    case low, high
}

protocol ProxiedContentDownloaderDelegate: AnyObject {
    /// uses the same semantics as:
    /// URLSessionDelegate#URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler;
    func proxiedContentDownloader(willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest) -> URLRequest?
}

// MARK: -

@objc
open class ProxiedContentAssetDescription: NSObject {
    @objc
    public let url: NSURL

    @objc
    public let fileExtension: String

    public init?(url: NSURL,
                 fileExtension: String? = nil) {
        self.url = url

        if let fileExtension = fileExtension {
            self.fileExtension = fileExtension
        } else {
            guard let pathExtension = url.pathExtension else {
                owsFailDebug("URL has not path extension.")
                return nil
            }
            self.fileExtension = pathExtension
        }
    }
}

// MARK: -

public enum ProxiedContentAssetSegmentState: UInt {
    case waiting
    case downloading
    case complete
    case failed
}

// MARK: -

public class ProxiedContentAssetSegment: NSObject {

    public let index: UInt
    public let segmentStart: UInt
    public let segmentLength: UInt
    // The amount of the segment that is overlap.  
    // The overlap lies in the _first_ n bytes of the segment data.
    public let redundantLength: UInt

    // This state should only be accessed on the main thread.
    public var state: ProxiedContentAssetSegmentState = .waiting {
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

// MARK: -

public enum ProxiedContentAssetRequestState: UInt {
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

// MARK: -

// Represents a request to download an asset.
//
// Should be cancelled if no longer necessary.
@objc
public class ProxiedContentAssetRequest: NSObject {

    let assetDescription: ProxiedContentAssetDescription
    let priority: ProxiedContentRequestPriority
    // Exactly one of success or failure should be called once,
    // on the main thread _unless_ this request is cancelled before
    // the request succeeds or fails.
    private var success: ((ProxiedContentAssetRequest?, ProxiedContentAsset) -> Void)?
    private var failure: ((ProxiedContentAssetRequest) -> Void)?

    var wasCancelled = false
    // This property is an internal implementation detail of the download process.
    var assetFilePath: String?

    // This state should only be accessed on the main thread.
    private var segments = [ProxiedContentAssetSegment]()
    public var state: ProxiedContentAssetRequestState = .waiting
    public var contentLength: Int = 0 {
        didSet {
            AssertIsOnMainThread()
            assert(oldValue == 0)
            assert(contentLength > 0)
        }
    }
    public weak var contentLengthTask: URLSessionDataTask?

    init(assetDescription: ProxiedContentAssetDescription,
         priority: ProxiedContentRequestPriority,
         success: @escaping ((ProxiedContentAssetRequest?, ProxiedContentAsset) -> Void),
         failure: @escaping ((ProxiedContentAssetRequest) -> Void)) {
        self.assetDescription = assetDescription
        self.priority = priority
        self.success = success
        self.failure = failure

        super.init()
    }

    private func segmentSize() -> UInt {
        AssertIsOnMainThread()

        let contentLength = UInt(self.contentLength)
        guard contentLength > 0 else {
            owsFailDebug("asset missing contentLength")
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

    fileprivate func createSegments(withInitialData initialData: Data) {
        AssertIsOnMainThread()

        let segmentLength = segmentSize()
        guard segmentLength > 0 else {
            return
        }
        let contentLength = UInt(self.contentLength)

        // Make the initial segment.
        let assetSegment = ProxiedContentAssetSegment(index: 0,
                                                      segmentStart: 0,
                                                      segmentLength: UInt(initialData.count),
                                                      redundantLength: 0)
        // "Download" the initial segment using the initialData.
        assetSegment.state = .downloading
        assetSegment.append(data: initialData)
        // Mark the initial segment as complete.
        assetSegment.state = .complete
        segments.append(assetSegment)

        var nextSegmentStart = UInt(initialData.count)
        var index: UInt = 1
        while nextSegmentStart < contentLength {
            var segmentStart: UInt = nextSegmentStart
            var redundantLength: UInt = 0
            // The last segment may overlap the penultimate segment
            // in order to keep the segment sizes uniform.
            if segmentStart + segmentLength > contentLength {
                redundantLength = segmentStart + segmentLength - contentLength
                segmentStart = contentLength - segmentLength
            }
            let assetSegment = ProxiedContentAssetSegment(index: index,
                                                 segmentStart: segmentStart,
                                                 segmentLength: segmentLength,
                                                 redundantLength: redundantLength)
            segments.append(assetSegment)
            nextSegmentStart = segmentStart + segmentLength
            index += 1
        }
    }

    private func firstSegmentWithState(state: ProxiedContentAssetSegmentState) -> ProxiedContentAssetSegment? {
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

    public func firstWaitingSegment() -> ProxiedContentAssetSegment? {
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

    public func writeAssetToFile(downloadFolderPath: String) -> ProxiedContentAsset? {

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

        let fileExtension = assetDescription.fileExtension
        let fileName = (NSUUID().uuidString as NSString).appendingPathExtension(fileExtension)!
        let filePath = (downloadFolderPath as NSString).appendingPathComponent(fileName)

        Logger.verbose("filePath: \(filePath).")

        do {
            try assetData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
            let asset = ProxiedContentAsset(assetDescription: assetDescription, filePath: filePath)
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

    public func requestDidSucceed(asset: ProxiedContentAsset) {
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

// MARK: -

// Represents a downloaded asset.
//
// The blob on disk is cleaned up when this instance is deallocated,
// so consumers of this resource should retain a strong reference to
// this instance as long as they are using the asset.
@objc
public class ProxiedContentAsset: NSObject {

    @objc
    public let assetDescription: ProxiedContentAssetDescription

    @objc
    public let filePath: String

    init(assetDescription: ProxiedContentAssetDescription,
         filePath: String) {
        self.assetDescription = assetDescription
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

// MARK: -

private var URLSessionTaskProxiedContentAssetRequest: UInt8 = 0
private var URLSessionTaskProxiedContentAssetSegment: UInt8 = 0

// This extension is used to punch an asset request onto a download task.
extension URLSessionTask {
    var assetRequest: ProxiedContentAssetRequest {
        get {
            return objc_getAssociatedObject(self, &URLSessionTaskProxiedContentAssetRequest) as! ProxiedContentAssetRequest
        }
        set {
            objc_setAssociatedObject(self, &URLSessionTaskProxiedContentAssetRequest, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    var assetSegment: ProxiedContentAssetSegment {
        get {
            return objc_getAssociatedObject(self, &URLSessionTaskProxiedContentAssetSegment) as! ProxiedContentAssetSegment
        }
        set {
            objc_setAssociatedObject(self, &URLSessionTaskProxiedContentAssetSegment, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: -

@objc
open class ProxiedContentDownloader: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {

    // MARK: - Properties

    private let downloadFolderName: String

    private var downloadFolderPath: String?

    // Force usage as a singleton
    public required init(downloadFolderName: String) {
        AssertIsOnMainThread()

        self.downloadFolderName = downloadFolderName

        super.init()

        SwiftSingletons.register(self)

        ensureDownloadFolder()
    }

    private lazy var downloadSession: URLSession = {
        AssertIsOnMainThread()

        let configuration = ContentProxy.sessionConfiguration()

        // Don't use any caching to protect privacy of these requests.
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
    private var assetMap = LRUCache<NSURL, ProxiedContentAsset>(maxSize: 100)
    // TODO: We could use a proper queue, e.g. implemented with a linked
    // list.
    private var assetRequestQueue = [ProxiedContentAssetRequest]()

    // The success and failure callbacks are always called on main queue.
    //
    // The success callbacks may be called synchronously on cache hit, in
    // which case the ProxiedContentAssetRequest parameter will be nil.
    public func requestAsset(assetDescription: ProxiedContentAssetDescription,
                             priority: ProxiedContentRequestPriority,
                             success: @escaping ((ProxiedContentAssetRequest?, ProxiedContentAsset) -> Void),
                             failure: @escaping ((ProxiedContentAssetRequest) -> Void)) -> ProxiedContentAssetRequest? {
        AssertIsOnMainThread()

        if let asset = assetMap.get(key: assetDescription.url) {
            // Synchronous cache hit.
            Logger.verbose("asset cache hit: \(assetDescription.url)")
            success(nil, asset)
            return nil
        }

        // Cache miss.
        //
        // Asset requests are done queued and performed asynchronously.
        Logger.verbose("asset cache miss: \(assetDescription.url)")
        let assetRequest = ProxiedContentAssetRequest(assetDescription: assetDescription,
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

    private func segmentRequestDidSucceed(assetRequest: ProxiedContentAssetRequest, assetSegment: ProxiedContentAssetSegment) {
        DispatchQueue.main.async {
            assetSegment.state = .complete

            if !self.tryToCompleteRequest(assetRequest: assetRequest) {
                self.processRequestQueueSync()
            }
        }
    }

    // Returns true if the request is completed.
    private func tryToCompleteRequest(assetRequest: ProxiedContentAssetRequest) -> Bool {
        AssertIsOnMainThread()

        guard assetRequest.areAllSegmentsComplete() else {
            return false
        }

        // If the asset request has completed all of its segments,
        // try to write the asset to file.
        assetRequest.state = .complete

        // Move write off main thread.
        DispatchQueue.global().async {
            guard let downloadFolderPath = self.downloadFolderPath else {
                owsFailDebug("Missing downloadFolderPath")
                return
            }
            guard let asset = assetRequest.writeAssetToFile(downloadFolderPath: downloadFolderPath) else {
                self.segmentRequestDidFail(assetRequest: assetRequest)
                return
            }
            self.assetRequestDidSucceed(assetRequest: assetRequest, asset: asset)
        }
        return true
    }

    private func assetRequestDidSucceed(assetRequest: ProxiedContentAssetRequest, asset: ProxiedContentAsset) {
        DispatchQueue.main.async {
            self.assetMap.set(key: assetRequest.assetDescription.url, value: asset)
            self.removeAssetRequestFromQueue(assetRequest: assetRequest)
            assetRequest.requestDidSucceed(asset: asset)
        }
    }

    private func segmentRequestDidFail(assetRequest: ProxiedContentAssetRequest, assetSegment: ProxiedContentAssetSegment? = nil) {
        DispatchQueue.main.async {
            if let assetSegment = assetSegment {
                assetSegment.state = .failed

                // TODO: If we wanted to implement segment retry, we'd do so here.
                //       For now, we just fail the entire asset request.
            }
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
        }
    }

    private func assetRequestDidFail(assetRequest: ProxiedContentAssetRequest) {

        DispatchQueue.main.async {
            self.removeAssetRequestFromQueue(assetRequest: assetRequest)
            assetRequest.requestDidFail()
        }
    }

    private func removeAssetRequestFromQueue(assetRequest: ProxiedContentAssetRequest) {
        AssertIsOnMainThread()

        guard assetRequestQueue.contains(assetRequest) else {
            Logger.warn("could not remove asset request from queue: \(assetRequest.assetDescription.url)")
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
        guard CurrentAppContext().isMainAppAndActive else {
            // If app is not active, fail the asset request.
            assetRequest.state = .failed
            assetRequestDidFail(assetRequest: assetRequest)
            processRequestQueueSync()
            return
        }

        if let asset = assetMap.get(key: assetRequest.assetDescription.url) {
            // Deferred cache hit, avoids re-downloading assets that were
            // downloaded while this request was queued.

            assetRequest.state = .complete
            assetRequestDidSucceed(assetRequest: assetRequest, asset: asset)
            return
        }

        if assetRequest.state == .waiting {
            // If asset request hasn't yet determined the resource size,
            // try to do so now, by requesting a small initial segment.
            assetRequest.state = .requestingSize

            let segmentStart: UInt = 0
            // Vary the initial segment size to obscure the length of the response headers.
            let segmentLength = UInt.random(in: 1024..<2048)
            var request = URLRequest(url: assetRequest.assetDescription.url as URL)
            request.httpShouldUsePipelining = true
            let rangeHeaderValue = "bytes=\(segmentStart)-\(segmentStart + segmentLength - 1)"
            request.setValue(rangeHeaderValue, forHTTPHeaderField: "Range")

            guard ContentProxy.configureProxiedRequest(request: &request) else {
                assetRequest.state = .failed
                assetRequestDidFail(assetRequest: assetRequest)
                processRequestQueueSync()
                return
            }

            let task = downloadSession.dataTask(with: request, completionHandler: { data, response, error -> Void in
                self.handleAssetSizeResponse(assetRequest: assetRequest, data: data, response: response, error: error)
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

            var request = URLRequest(url: assetRequest.assetDescription.url as URL)
            request.httpShouldUsePipelining = true
            let rangeHeaderValue = "bytes=\(assetSegment.segmentStart)-\(assetSegment.segmentStart + assetSegment.segmentLength - 1)"
            request.setValue(rangeHeaderValue, forHTTPHeaderField: "Range")

            guard ContentProxy.configureProxiedRequest(request: &request) else {
                assetRequest.state = .failed
                assetRequestDidFail(assetRequest: assetRequest)
                processRequestQueueSync()
                return
            }

            let task: URLSessionDataTask = downloadSession.dataTask(with: request)
            task.assetRequest = assetRequest
            task.assetSegment = assetSegment
            assetSegment.task = task
            task.resume()
        }

        // Recurse; we may be able to start multiple downloads.
        processRequestQueueSync()
    }

    private func handleAssetSizeResponse(assetRequest: ProxiedContentAssetRequest, data: Data?, response: URLResponse?, error: Error?) {
        guard error == nil else {
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        guard let data = data,
        data.count > 0 else {
            owsFailDebug("Asset size response missing data.")
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
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            Logger.warn("invalid httpResponse.statusCode: \(httpResponse.statusCode)")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }
        var firstContentRangeString: String?
        for header in httpResponse.allHeaderFields.keys {
            guard let headerString = header as? String else {
                owsFailDebug("Invalid header: \(header)")
                continue
            }
            if headerString.lowercased() == "content-range" {
                firstContentRangeString = httpResponse.allHeaderFields[header] as? String
            }
        }
        guard let contentRangeString = firstContentRangeString else {
            owsFailDebug("Asset size response is missing content range.")
            assetRequest.state = .failed
            self.assetRequestDidFail(assetRequest: assetRequest)
            return
        }

        // Example: content-range: bytes 0-1023/7630
        guard let contentLengthString = NSRegularExpression.parseFirstMatch(pattern: "^bytes \\d+\\-\\d+/(\\d+)$",
                                                              text: contentRangeString) else {
                                                                owsFailDebug("Asset size response has invalid content range.")
                                                                assetRequest.state = .failed
                                                                self.assetRequestDidFail(assetRequest: assetRequest)
                                                                return
        }
        guard
            !contentLengthString.isEmpty,
            let contentLength = Int(contentLengthString)
        else {
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
            assetRequest.createSegments(withInitialData: data)
            assetRequest.state = .active

            if !self.tryToCompleteRequest(assetRequest: assetRequest) {
                self.processRequestQueueSync()
            }
        }
    }

    // Return the first asset request for which we either:
    //
    // * Need to download the content length.
    // * Need to download at least one of its segments.
    private func popNextAssetRequest() -> ProxiedContentAssetRequest? {
        AssertIsOnMainThread()

        let kMaxAssetRequestCount: UInt = 3
        let kMaxAssetRequestsPerAssetCount: UInt = kMaxAssetRequestCount - 1

        // Prefer the first "high" priority request;
        // fall back to the first "low" priority request.
        var activeAssetRequestsCount: UInt = 0
        for priority in [ProxiedContentRequestPriority.high, ProxiedContentRequestPriority.low] {
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

    weak var delegate: ProxiedContentDownloaderDelegate?
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let delegate = delegate else {
            completionHandler(request)
            return
        }

        let delegateRequest = delegate.proxiedContentDownloader(willPerformHTTPRedirection: response, newRequest: request)
        completionHandler(delegateRequest)
    }

    // MARK: Temp Directory

    public func ensureDownloadFolder() {
        // We write assets to the temporary directory so that iOS can clean them up.
        // We try to eagerly clean up these assets when they are no longer in use.

        let tempDirPath = OWSTemporaryDirectory()
        let dirPath = (tempDirPath as NSString).appendingPathComponent(downloadFolderName)
        do {
            let fileManager = FileManager.default

            // Try to delete existing folder if necessary.
            if fileManager.fileExists(atPath: dirPath) {
                try fileManager.removeItem(atPath: dirPath)
                downloadFolderPath = dirPath
            }
            // Try to create folder if necessary.
            if !fileManager.fileExists(atPath: dirPath) {
                try fileManager.createDirectory(atPath: dirPath,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
                downloadFolderPath = dirPath
            }

            // Don't back up ProxiedContent downloads.
            OWSFileSystem.protectFileOrFolder(atPath: dirPath)
        } catch let error as NSError {
            owsFailDebug("ensureTempFolder failed: \(dirPath), \(error)")
            downloadFolderPath = tempDirPath
        }
    }
}
