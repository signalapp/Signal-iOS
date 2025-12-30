//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class InternalFileBrowserViewController: OWSTableViewController2 {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileManager = .default
        self.fileURL = fileURL

        super.init()

        self.contents = buildContents()
    }

    private func buildContents() -> OWSTableContents {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return OWSTableContents(title: "File not found: \(fileURL)")
        }

        var sections = [OWSTableSection]()

        // Put the URL somewhere it'll wrap and is copyable.
        sections.append(OWSTableSection(items: [
            .copyableItem(
                label: "Current File URL",
                value: fileURL.absoluteString,
            ),
        ]))

        if isDirectory.boolValue {
            let directoryContents: [URL]
            do {
                directoryContents = try fileManager.contentsOfDirectory(
                    at: fileURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                )
            } catch {
                owsFailDebug("Failed to get contents of \(fileURL)! \(error)")
                directoryContents = []
            }

            let fileItems: [OWSTableItem] = directoryContents.map { contentsUrl in
                let fileIsDirectory: Bool
                do {
                    fileIsDirectory = try contentsUrl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory!
                } catch {
                    owsFailDebug("Failed to get isDirectory resource value! \(error)")
                    fileIsDirectory = false
                }

                let icon = fileIsDirectory ? "📁" : "📄"

                return .disclosureItem(
                    withText: "\(icon): \(contentsUrl.lastPathComponent)",
                    actionBlock: { [weak self] in
                        guard let self else { return }
                        navigationController?.pushViewController(
                            InternalFileBrowserViewController(fileURL: contentsUrl),
                            animated: true,
                        )
                    },
                )
            }

            sections.append(OWSTableSection(
                title: "Contents",
                items: fileItems,
            ))
        }

        do {
            let attributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: fileURL.path)

            let attributeItems: [OWSTableItem] = attributes
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { fileAttribute, value in
                    return .copyableItem(
                        label: fileAttribute.rawValue.replacingOccurrences(of: "NSFile", with: ""),
                        value: "\(value)",
                    )
                }

            sections.append(OWSTableSection(
                title: "Attributes",
                items: attributeItems,
            ))
        } catch {
            owsFailDebug("Failed to get attributes for \(fileURL)! \(error)")
        }

        return OWSTableContents(sections: sections)
    }
}
