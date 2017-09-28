//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

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

    init(giphyId: String,
         renditions: [GiphyRendition]) {
        self.giphyId = giphyId
        self.renditions = renditions
    }

    let kMaxDimension = UInt(618)
    let kMinDimension = UInt(101)
    let kMaxFileSize = SignalAttachment.kMaxFileSizeAnimatedImage

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

    private func giphySessionManager() -> AFHTTPSessionManager? {
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

    // TODO:
    public func test() {
        search(query:"monkey",
               success: { _ in
        }, failure: {
        })
    }

    public func search(query: String, success: @escaping (([GiphyImageInfo]) -> Void), failure: @escaping (() -> Void)) {
        guard let sessionManager = giphySessionManager() else {
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
//        Logger.debug("\(GifManager.TAG) Image successfully parsed.")
        return GiphyImageInfo(giphyId : giphyId,
                              renditions : renditions)
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
}
