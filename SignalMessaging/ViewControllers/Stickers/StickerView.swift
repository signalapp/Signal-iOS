//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

@objc
public class StickerView: YYAnimatedImageView {

    private let stickerInfo: StickerInfo

    // MARK: - Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init(stickerInfo: StickerInfo, size: CGFloat? = nil) {
        self.stickerInfo = stickerInfo

        super.init(frame: .zero)

        if let size = size {
            autoSetDimensions(to: CGSize(width: size, height: size))
        }

        loadSticker()
    }

    // MARK: -

    private func loadSticker() {
        guard let filePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo) else {
            Logger.warn("Sticker not yet installed.")
            return
        }
        guard NSData.ows_isValidImage(atPath: filePath, mimeType: OWSMimeTypeImageWebp) else {
            owsFailDebug("Invalid sticker.")
            return
        }
        // TODO: Asset to show while loading a sticker - if any.
        guard let stickerImage = YYImage(contentsOfFile: filePath) else {
            owsFailDebug("Sticker could not be parsed.")
            return
        }

        image = stickerImage
    }
}
