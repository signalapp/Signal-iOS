//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSLinkPreview)
public class LinkPreview: MTLModel {
    @objc
    public var urlString: String?

    @objc
    public var title: String?

    @objc
    public var attachmentId: String?

    @objc
    public init(urlString: String, title: String?, attachmentId: String?) {
        self.urlString = urlString
        self.title = title
        self.attachmentId = attachmentId

        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
}
