//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC

enum GiphyFormat {
    case gif, webp, mp4
}

@objc class GiphyRendition: NSObject {
    let format: GiphyFormat
    let name: String
    let width: UInt
    let height: UInt
    let fileSize: UInt
    let url: NSURL

    init(format: GiphyFormat,
         name: String,
         width: UInt,
         height: UInt,
         fileSize: UInt,
         url: NSURL) {
        self.format = format
        self.name = name
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.url = url
    }
}

@objc class GiphyImageInfo: NSObject {
    let giphyId: String
    let renditions: [GiphyRendition]
    let originalRendition: GiphyRendition

    init(giphyId: String,
         renditions: [GiphyRendition],
         originalRendition: GiphyRendition) {
        self.giphyId = giphyId
        self.renditions = renditions
        self.originalRendition = originalRendition
    }

    // TODO:
    let kMaxDimension = UInt(618)
    let kMinDimension = UInt(101)
    let kMaxFileSize = UInt(3 * 1024 * 1024)

    public func pickGifRendition() -> GiphyRendition? {
        var bestRendition: GiphyRendition?

        for rendition in renditions {
            guard rendition.format == .gif else {
                continue
            }
            guard !rendition.name.hasSuffix("_still")
                else {
                    continue
            }
            guard rendition.width >= kMinDimension &&
                rendition.width <= kMaxDimension &&
                rendition.height >= kMinDimension &&
                rendition.height <= kMaxDimension &&
                rendition.fileSize <= kMaxFileSize
                else {
                    continue
            }

            if let currentBestRendition = bestRendition {
                if rendition.width > currentBestRendition.width {
                    bestRendition = rendition
                }
            } else {
                bestRendition = rendition
            }
        }

        return bestRendition
    }
}

@objc class GiphyAssetRequest: NSObject {
    static let TAG = "[GiphyAssetRequest]"

    let rendition: GiphyRendition
    let success: ((GiphyAsset) -> Void)
    let failure: (() -> Void)
    var wasCancelled = false
    var assetFilePath: String?

    init(rendition: GiphyRendition,
         success:@escaping ((GiphyAsset) -> Void),
         failure:@escaping (() -> Void)
        ) {
        self.rendition = rendition
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

@objc class GifManager: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {

    // MARK: - Properties

    static let TAG = "[GifManager]"

    static let sharedInstance = GifManager()

    private let operationQueue = OperationQueue()

    // Force usage as a singleton
    override private init() {}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let kGiphyBaseURL = "https://api.giphy.com/"

    private func giphyAPISessionManager() -> AFHTTPSessionManager? {
        guard let baseUrl = NSURL(string:kGiphyBaseURL) else {
            Logger.error("\(GifManager.TAG) Invalid base URL.")
            return nil
        }
        // TODO: Is this right?
        let sessionConf = URLSessionConfiguration.ephemeral
        // TODO: Is this right?
        sessionConf.connectionProxyDictionary = [
            kCFProxyHostNameKey as String: "giphy-proxy-production.whispersystems.org",
            kCFProxyPortNumberKey as String: "80",
            kCFProxyTypeKey as String: kCFProxyTypeHTTPS
        ]

        let sessionManager = AFHTTPSessionManager(baseURL:baseUrl as URL,
                                                  sessionConfiguration:sessionConf)
        sessionManager.requestSerializer = AFJSONRequestSerializer()
        sessionManager.responseSerializer = AFJSONResponseSerializer()

        return sessionManager
    }

    private func giphyDownloadSession() -> URLSession? {
//        guard let baseUrl = NSURL(string:kGiphyBaseURL) else {
//            Logger.error("\(GifManager.TAG) Invalid base URL.")
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
//        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
//
//        let sessionManager = AFHTTPSessionManager(baseURL:baseUrl as URL,
//                                                  sessionConfiguration:sessionConf)
//        sessionManager.requestSerializer = AFJSONRequestSerializer()
//        sessionManager.responseSerializer = AFJSONResponseSerializer()
//        
//        return sessionManager
    }

    // TODO:
    public func test() {
        search(query:"monkey",
               success: { _ in
        }, failure: {
        })
    }

    // MARK: Search

    public func search(query: String, success: @escaping (([GiphyImageInfo]) -> Void), failure: @escaping (() -> Void)) {
        guard let sessionManager = giphyAPISessionManager() else {
            Logger.error("\(GifManager.TAG) Couldn't create session manager.")
            failure()
            return
        }
        guard NSURL(string:kGiphyBaseURL) != nil else {
            Logger.error("\(GifManager.TAG) Invalid base URL.")
            failure()
            return
        }

        // TODO: Should we use a separate API key?
        let kGiphyApiKey = "3o6ZsYH6U6Eri53TXy"
        let kGiphyPageSize = 200
        // TODO:
        let kGiphyPageOffset = 0
        guard let queryEncoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            Logger.error("\(GifManager.TAG) Could not URL encode query: \(query).")
            failure()
            return
        }
        let urlString = "/v1/gifs/search?api_key=\(kGiphyApiKey)&offset=\(kGiphyPageOffset)&limit=\(kGiphyPageSize)&q=\(queryEncoded)"

        sessionManager.get(urlString,
                           parameters: {},
                           progress:nil,
                           success: { _, value in
                            Logger.error("\(GifManager.TAG) search request succeeded")
                            guard let imageInfos = self.parseGiphyImages(responseJson:value) else {
                                failure()
                                return
                            }
                            success(imageInfos)
        },
                           failure: { _, error in
                            Logger.error("\(GifManager.TAG) search request failed: \(error)")
                            failure()
        })
    }

    // MARK: Parse API Responses

    private func parseGiphyImages(responseJson:Any?) -> [GiphyImageInfo]? {
        guard let responseJson = responseJson else {
            Logger.error("\(GifManager.TAG) Missing response.")
            return nil
        }
        guard let responseDict = responseJson as? [String:Any] else {
            Logger.error("\(GifManager.TAG) Invalid response.")
            return nil
        }
        guard let imageDicts = responseDict["data"] as? [[String:Any]] else {
            Logger.error("\(GifManager.TAG) Invalid response data.")
            return nil
        }
        var result = [GiphyImageInfo]()
        for imageDict in imageDicts {
            guard let imageInfo = parseGiphyImage(imageDict:imageDict) else {
                continue
            }
            result.append(imageInfo)
        }
        return result
    }

    private func parseGiphyImage(imageDict: [String:Any]) -> GiphyImageInfo? {
        guard let giphyId = imageDict["id"] as? String else {
            Logger.warn("\(GifManager.TAG) Image dict missing id.")
            return nil
        }
        guard giphyId.characters.count > 0 else {
            Logger.warn("\(GifManager.TAG) Image dict has invalid id.")
            return nil
        }
        guard let renditionDicts = imageDict["images"] as? [String:Any] else {
            Logger.warn("\(GifManager.TAG) Image dict missing renditions.")
            return nil
        }
        var renditions = [GiphyRendition]()
        for (renditionName, renditionDict) in renditionDicts {
            guard let renditionDict = renditionDict as? [String:Any] else {
                Logger.warn("\(GifManager.TAG) Invalid rendition dict.")
                continue
            }
            guard let rendition = parseGiphyRendition(renditionName:renditionName,
                                                      renditionDict:renditionDict) else {
                                                        continue
            }
            renditions.append(rendition)
        }
        guard renditions.count > 0 else {
            Logger.warn("\(GifManager.TAG) Image has no valid renditions.")
            return nil
        }

        guard let originalRendition = findOriginalRendition(renditions:renditions) else {
            Logger.warn("\(GifManager.TAG) Image has no original rendition.")
            return nil
        }

//        Logger.debug("\(GifManager.TAG) Image successfully parsed.")
        return GiphyImageInfo(giphyId : giphyId,
                              renditions : renditions,
                              originalRendition: originalRendition)
    }

    private func findOriginalRendition(renditions: [GiphyRendition]) -> GiphyRendition? {
        for rendition in renditions {
            if rendition.name == "original" {
                return rendition
            }
        }
        return nil
    }

    private func parseGiphyRendition(renditionName: String,
                                     renditionDict: [String:Any]) -> GiphyRendition? {
        guard let width = parsePositiveUInt(dict:renditionDict, key:"width", typeName:"rendition") else {
            return nil
        }
        guard let height = parsePositiveUInt(dict:renditionDict, key:"height", typeName:"rendition") else {
            return nil
        }
        guard let fileSize = parsePositiveUInt(dict:renditionDict, key:"size", typeName:"rendition") else {
            return nil
        }
        guard let urlString = renditionDict["url"] as? String else {
            Logger.debug("\(GifManager.TAG) Rendition missing url.")
            return nil
        }
        guard urlString.characters.count > 0 else {
            Logger.warn("\(GifManager.TAG) Rendition has invalid url.")
            return nil
        }
        guard let url = NSURL(string:urlString) else {
            Logger.warn("\(GifManager.TAG) Rendition url could not be parsed.")
            return nil
        }
        guard let fileExtension = url.pathExtension else {
            Logger.warn("\(GifManager.TAG) Rendition url missing file extension.")
            return nil
        }
        guard fileExtension.lowercased() == "gif" else {
//            Logger.verbose("\(GifManager.TAG) Rendition has invalid type: \(fileExtension).")
            return nil
        }

//        Logger.debug("\(GifManager.TAG) Rendition successfully parsed.")
        return GiphyRendition(
            format : .gif,
            name : renditionName,
            width : width,
            height : height,
            fileSize : fileSize,
            url : url
        )
    }

    // Giphy API results are often incompl
    //
    //    {
    //    height = 65;
    //    mp4 = "https://media3.giphy.com/media/42YlR8u9gV5Cw/100w.mp4";
    //    "mp4_size" = 34584;
    //    size = 246393;
    //    url = "https://media3.giphy.com/media/42YlR8u9gV5Cw/100w.gif";
    //    webp = "https://media3.giphy.com/media/42YlR8u9gV5Cw/100w.webp";
    //    "webp_size" = 63656;
    //    width = 100;
    //    }
    private func parsePositiveUInt(dict: [String:Any], key: String, typeName: String) -> UInt? {
        guard let value = dict[key] else {
//            Logger.verbose("\(GifManager.TAG) \(typeName) missing \(key).")
            return nil
        }
        guard let stringValue = value as? String else {
//            Logger.verbose("\(GifManager.TAG) \(typeName) has invalid \(key): \(value).")
            return nil
        }
        guard let parsedValue = UInt(stringValue) else {
//            Logger.verbose("\(GifManager.TAG) \(typeName) has invalid \(key): \(stringValue).")
            return nil
        }
        guard parsedValue > 0 else {
            Logger.verbose("\(GifManager.TAG) \(typeName) has non-positive \(key): \(parsedValue).")
            return nil
        }
        return parsedValue
    }

    // MARK: Rendition Download

    // TODO: Use a proper cache.
    private var assetMap = [NSURL: GiphyAsset]()
    // TODO: We could use a proper queue.
    private var assetRequestQueue = [GiphyAssetRequest]()
    private var isDownloading = false

    // The success and failure handlers are always called on main queue.
    // The success and failure handlers may be called synchronously on cache hit.
    public func downloadAssetAsync(rendition: GiphyRendition,
                              success:@escaping ((GiphyAsset) -> Void),
                              failure:@escaping (() -> Void)) -> GiphyAssetRequest? {
        AssertIsOnMainThread()

        if let asset = assetMap[rendition.url] {
            success(asset)
            return nil
        }

        let assetRequest = GiphyAssetRequest(rendition:rendition,
                                             success : { asset in
                                                DispatchQueue.main.async {
                                                    self.assetMap[rendition.url] = asset
                                                    success(asset)
                                                    self.isDownloading = false
                                                    self.downloadIfNecessary()
                                                }
        },
                                             failure : {
                                                DispatchQueue.main.async {
                                                    failure()
                                                    self.isDownloading = false
                                                    self.downloadIfNecessary()
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
            guard self.assetRequestQueue.count > 0 else {
                return
            }
            guard let assetRequest = self.assetRequestQueue.first else {
                owsFail("\(GiphyAsset.TAG) could not pop asset requests")
                return
            }
            self.assetRequestQueue.removeFirst()
            guard !assetRequest.wasCancelled else {
                DispatchQueue.main.async {
                    self.downloadIfNecessary()
                }
                return
            }
            self.isDownloading = true

            if let asset = self.assetMap[assetRequest.rendition.url] {
                // Deferred cache hit, avoids re-downloading assets already in the 
                // asset cache.
                assetRequest.success(asset)
                return
            }

            guard let downloadSession = self.giphyDownloadSession() else {
                Logger.error("\(GifManager.TAG) Couldn't create session manager.")
                assetRequest.failure()
                return
            }

            let task = downloadSession.downloadTask(with:assetRequest.rendition.url as URL)
            task.assetRequest = assetRequest
            task.resume()
        }
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
            return
        }
        if let error = error {
            Logger.error("\(GifManager.TAG) download failed with error: \(error)")
            assetRequest.failure()
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse else {
            Logger.error("\(GifManager.TAG) missing or unexpected response: \(task.response)")
            assetRequest.failure()
            return
        }
        let statusCode = httpResponse.statusCode
        guard statusCode >= 200 && statusCode < 400 else {
            Logger.error("\(GifManager.TAG) response has invalid status code: \(statusCode)")
            assetRequest.failure()
            return
        }
        guard let assetFilePath = assetRequest.assetFilePath else {
            Logger.error("\(GifManager.TAG) task is missing asset file")
            assetRequest.failure()
            return
        }
        Logger.verbose("\(GifManager.TAG) download succeeded: \(assetRequest.rendition.url)")
        let asset = GiphyAsset(rendition: assetRequest.rendition, filePath : assetFilePath)
        assetRequest.success(asset)
    }

    // MARK: URLSessionDownloadDelegate

    private func fileExtension(forFormat format: GiphyFormat) -> String {
        switch format {
        case .gif:
            return "gif"
        case .webp:
            return "webp"
        case .mp4:
            return "mp4"
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            return
        }

        let dirPath = NSTemporaryDirectory()
        let fileExtension = self.fileExtension(forFormat:assetRequest.rendition.format)
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
            return
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        let assetRequest = downloadTask.assetRequest
        guard !assetRequest.wasCancelled else {
            downloadTask.cancel()
            return
        }
    }
}
