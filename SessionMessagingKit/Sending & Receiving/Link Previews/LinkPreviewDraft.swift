// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public struct LinkPreviewDraft: Equatable, Hashable {
    public var urlString: String
    public var title: String?
    public var jpegImageData: Data?

    public init(urlString: String, title: String?, jpegImageData: Data? = nil) {
        self.urlString = urlString
        self.title = title
        self.jpegImageData = jpegImageData
    }

    public func isValid() -> Bool {
        var hasTitle = false
        
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        
        let hasImage = jpegImageData != nil
        
        return (hasTitle || hasImage)
    }
}
