//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc public enum ImageEditorError: Int, Error {
    case assertionError
    case invalidInput
}

@objc
public class ImageEditorItem: NSObject {
    @objc
    public let itemId: String

    @objc
    public override required init() {
        self.itemId = UUID().uuidString

        super.init()
    }
}

@objc
public class ImageEditorModel: NSObject {
    private let srcImagePath: String
    private let srcImageSize: CGSize

    @objc
    public required init(srcImagePath: String) throws {
        self.srcImagePath = srcImagePath

        let srcFileName = (srcImagePath as NSString).lastPathComponent
        let srcFileExtension = (srcFileName as NSString).pathExtension
        guard let mimeType = MIMETypeUtil.mimeType(forFileExtension: srcFileExtension) else {
            Logger.error("Couldn't determine MIME type for file.")
            throw ImageEditorError.invalidInput
        }
        guard MIMETypeUtil.isImage(mimeType) else {
            Logger.error("Invalid MIME type: \(mimeType).")
            throw ImageEditorError.invalidInput
        }

        let srcImageSize = NSData.imageSize(forFilePath: srcImagePath, mimeType: mimeType)
        guard srcImageSize.width > 0, srcImageSize.height > 0 else {
            Logger.error("Couldn't determine image size.")
            throw ImageEditorError.invalidInput
        }
        self.srcImageSize = srcImageSize

        super.init()
    }
}
