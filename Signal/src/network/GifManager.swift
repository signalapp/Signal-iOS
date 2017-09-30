//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import ObjectiveC

// There's no UTI type for webp!
enum GiphyFormat {
    case gif, mp4, jpg
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

    public func fileExtension() -> String {
        switch format {
        case .gif:
            return "gif"
        case .mp4:
            return "mp4"
        case .jpg:
            return "jpg"
        }
    }

    public func utiType() -> String {
        switch format {
        case .gif:
            return kUTTypeGIF as String
        case .mp4:
            return kUTTypeMPEG4 as String
        case .jpg:
            return kUTTypeJPEG as String
        }
    }

    public func log() {
        Logger.verbose("\t \(format), \(name), \(width), \(height), \(fileSize)")
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

    private enum PickingStrategy {
        case smallerIsBetter, largerIsBetter
    }

    public func log() {
        Logger.verbose("giphyId: \(giphyId), \(renditions.count)")
        for rendition in renditions {
            rendition.log()
        }
    }

    public func pickStillRendition() -> GiphyRendition? {
        return pickRendition(isStill:true, pickingStrategy:.smallerIsBetter, maxFileSize:kMaxFileSize)
    }

    public func pickGifRendition() -> GiphyRendition? {
        // Try to pick a small file...
        if let rendition = pickRendition(isStill:false, pickingStrategy:.largerIsBetter, maxFileSize:kMaxFileSize) {
            return rendition
        }
        // ...but gradually relax the file restriction...
        if let rendition = pickRendition(isStill:false, pickingStrategy:.smallerIsBetter, maxFileSize:kMaxFileSize * 2) {
            return rendition
        }
        // ...and relax even more.
        return pickRendition(isStill:false, pickingStrategy:.smallerIsBetter, maxFileSize:kMaxFileSize * 3)
    }

    private func pickRendition(isStill: Bool, pickingStrategy: PickingStrategy, maxFileSize: UInt) -> GiphyRendition? {
        var bestRendition: GiphyRendition?

        for rendition in renditions {
            if isStill {
                guard [.gif, .jpg].contains(rendition.format) else {
                    continue
                }
                guard rendition.name.hasSuffix("_still") else {
                        continue
                }
                // Accept renditions without a valid file size.
                guard rendition.width >= kMinDimension &&
                    rendition.height >= kMinDimension &&
                    rendition.fileSize <= maxFileSize
                    else {
                        continue
                }
            } else {
                guard rendition.format == .gif else {
                    continue
                }
                guard !rendition.name.hasSuffix("_still") else {
                        continue
                }
                guard !rendition.name.hasSuffix("_downsampled") else {
                        continue
                }
                guard rendition.width >= kMinDimension &&
                    rendition.width <= kMaxDimension &&
                    rendition.height >= kMinDimension &&
                    rendition.height <= kMaxDimension &&
                    rendition.fileSize > 0 &&
                    rendition.fileSize <= maxFileSize
                    else {
                        continue
                }
            }

            if let currentBestRendition = bestRendition {
                if pickingStrategy == .smallerIsBetter {
                    if rendition.width < currentBestRendition.width {
                        bestRendition = rendition
                    }
                } else {
                    if rendition.width > currentBestRendition.width {
                        bestRendition = rendition
                    }
                }
            } else {
                bestRendition = rendition
            }
        }

        return bestRendition
    }
}

@objc class GifManager: NSObject {

    // MARK: - Properties

    static let TAG = "[GifManager]"

    static let sharedInstance = GifManager()

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

    // Giphy API results are often incomplete or malformed, so we need to be defensive.
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

    // Giphy API results are often incomplete or malformed, so we need to be defensive.
    private func parseGiphyRendition(renditionName: String,
                                     renditionDict: [String:Any]) -> GiphyRendition? {
        guard let width = parsePositiveUInt(dict:renditionDict, key:"width", typeName:"rendition") else {
            return nil
        }
        guard let height = parsePositiveUInt(dict:renditionDict, key:"height", typeName:"rendition") else {
            return nil
        }
        // Be lenient when parsing file sizes - we don't require them for stills.
        let fileSize = parseLenientUInt(dict:renditionDict, key:"size")
        guard let urlString = renditionDict["url"] as? String else {
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
        var format = GiphyFormat.gif
        if fileExtension.lowercased() == "gif" {
            format = .gif
        } else if fileExtension.lowercased() == "jpg" {
            format = .jpg
        } else if fileExtension.lowercased() == "mp4" {
            format = .mp4
        } else if fileExtension.lowercased() == "webp" {
            return nil
        } else {
            Logger.warn("\(GifManager.TAG) Invalid file extension: \(fileExtension).")
            return nil
        }

        return GiphyRendition(
            format : format,
            name : renditionName,
            width : width,
            height : height,
            fileSize : fileSize,
            url : url
        )
    }

    private func parsePositiveUInt(dict: [String:Any], key: String, typeName: String) -> UInt? {
        guard let value = dict[key] else {
            return nil
        }
        guard let stringValue = value as? String else {
            return nil
        }
        guard let parsedValue = UInt(stringValue) else {
            return nil
        }
        guard parsedValue > 0 else {
            Logger.verbose("\(GifManager.TAG) \(typeName) has non-positive \(key): \(parsedValue).")
            return nil
        }
        return parsedValue
    }

    private func parseLenientUInt(dict: [String:Any], key: String) -> UInt {
        let defaultValue = UInt(0)

        guard let value = dict[key] else {
            return defaultValue
        }
        guard let stringValue = value as? String else {
            return defaultValue
        }
        guard let parsedValue = UInt(stringValue) else {
            return defaultValue
        }
        return parsedValue
    }
}
