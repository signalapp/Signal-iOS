//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSTableContents {

    public private(set) var title: String?

    public private(set) var sections: [OWSTableSection] = []

    public var sectionForSectionIndexTitleBlock: ((String, Int) -> Int)?

    public var sectionIndexTitlesForTableViewBlock: (() -> [String])?

    public init(title: String? = nil, sections: [OWSTableSection] = []) {
        self.title = title
        self.sections = sections
    }

    public func add(_ section: OWSTableSection) {
        sections.append(section)
    }

    public func add<T: Sequence>(sections: T) where T.Element == OWSTableSection {
        self.sections.append(contentsOf: sections)
    }
}
