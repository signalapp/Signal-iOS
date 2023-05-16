//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSTableContents: NSObject {

    public private(set) var title: String?

    @objc
    public private(set) var sections: [OWSTableSection] = []

    @objc
    public var sectionForSectionIndexTitleBlock: ((String, Int) -> Int)?

    @objc
    public var sectionIndexTitlesForTableViewBlock: (() -> [String])?

    public init(title: String? = nil, sections: [OWSTableSection] = []) {
        self.title = title
        self.sections = sections
        super.init()
    }

    public convenience override init() {
        self.init(title: nil, sections: [])
    }

    @objc
    public func addSection(_ section: OWSTableSection) {
        sections.append(section)
    }

    public func addSections<T: Sequence>(_ sections: T) where T.Element == OWSTableSection {
        self.sections.append(contentsOf: sections)
    }
}
