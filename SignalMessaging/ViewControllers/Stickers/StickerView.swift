//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage
import Lottie

@objc
public class StickerView: NSObject {

    // Never instantiate this class.
    private override init() {}

    public static func stickerView(forStickerInfo stickerInfo: StickerInfo,
                                   dataSource: StickerPackDataSource,
                                   size: CGFloat? = nil) -> UIView? {
        guard let stickerMetadata = dataSource.metadata(forSticker: stickerInfo) else {
            Logger.warn("Missing sticker metadata.")
            return nil
        }
        return stickerView(stickerInfo: stickerInfo, stickerMetadata: stickerMetadata, size: size)
    }

    public static func stickerView(forInstalledStickerInfo stickerInfo: StickerInfo,
                                   size: CGFloat? = nil) -> UIView? {
        let metadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo)
        guard let stickerMetadata = metadata else {
            Logger.warn("Missing sticker metadata.")
            return nil
        }
        return stickerView(stickerInfo: stickerInfo, stickerMetadata: stickerMetadata, size: size)
    }

    private static func stickerView(stickerInfo: StickerInfo,
                                    stickerMetadata: StickerMetadata,
                                    size: CGFloat? = nil) -> UIView? {

        let stickerDataUrl = stickerMetadata.stickerDataUrl

        guard let stickerView = self.stickerView(stickerInfo: stickerInfo,
                                                 stickerType: stickerMetadata.stickerType,
                                                 stickerDataUrl: stickerDataUrl) else {
            Logger.warn("Could not load sticker for display.")
            return nil
        }
        if let size = size {
            stickerView.autoSetDimensions(to: CGSize(square: size))
        }
        return stickerView
    }

    static func stickerView(stickerInfo: StickerInfo,
                            stickerType: StickerType,
                            stickerDataUrl: URL) -> UIView? {

        guard OWSFileSystem.fileOrFolderExists(url: stickerDataUrl) else {
            Logger.warn("Sticker path does not exist: \(stickerDataUrl).")
            return nil
        }

        guard NSData.ows_isValidImage(at: stickerDataUrl, mimeType: stickerType.contentType) else {
            owsFailDebug("Invalid sticker.")
            return nil
        }

        let stickerView: UIView
        switch stickerType {
        case .webp, .apng, .gif:
            guard let stickerImage = YYImage(contentsOfFile: stickerDataUrl.path) else {
                owsFailDebug("Sticker could not be parsed.")
                return nil
            }
            let yyView = YYAnimatedImageView()
            yyView.alwaysInfiniteLoop = true
            yyView.contentMode = .scaleAspectFit
            yyView.image = stickerImage
            stickerView = yyView
        case .signalLottie:
            let lottieView = Lottie.AnimationView(filePath: stickerDataUrl.path)
            lottieView.contentMode = .scaleAspectFit
            lottieView.animationSpeed = 1
            lottieView.loopMode = .loop
            lottieView.backgroundBehavior = .pause
            lottieView.play()
            stickerView = lottieView
        }
        return stickerView
    }
}
