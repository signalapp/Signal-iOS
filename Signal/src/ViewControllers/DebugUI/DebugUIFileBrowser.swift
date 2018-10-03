//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc class DebugUIFileBrowser: OWSTableViewController {

    // MARK: Dependencies
    var fileManager: FileManager {
        return FileManager.default
    }

    // MARK: Overrides
    let fileURL: URL

    @objc init(fileURL: URL) {
        self.fileURL = fileURL

        super.init(nibName: nil, bundle: nil)

        self.contents = buildContents()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let titleLabel = UILabel()
        titleLabel.text = "\(fileURL)"
        titleLabel.sizeToFit()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.lineBreakMode = .byTruncatingHead
        self.navigationItem.titleView = titleLabel
    }

    fileprivate func updateContents() {
        self.contents = buildContents()
        self.tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // In case files were added / removed in child view controller
        updateContents()
    }

    func buildContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let isDirectoryPtr: UnsafeMutablePointer<ObjCBool> = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: isDirectoryPtr) else {
            contents.title = "File not found: \(fileURL)"
            return contents
        }

        let isDirectory: Bool = isDirectoryPtr.pointee.boolValue

        if isDirectory {
            var fileItems: [OWSTableItem] = []
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey]

            let directoryContents: [URL] = {
                do {
                    return try fileManager.contentsOfDirectory(at: fileURL,
                                                               includingPropertiesForKeys: resourceKeys)
                } catch {
                    owsFailDebug("contentsOfDirectory(\(fileURL) failed with error: \(error)")
                    return []
                }
            }()

            fileItems = directoryContents.map { fileInDirectory in
                let fileIcon: String = {
                    do {
                        guard let isDirectory = try fileInDirectory.resourceValues(forKeys: Set(resourceKeys)).isDirectory else {
                            owsFailDebug("unable to check isDirectory for file: \(fileInDirectory)")
                            return ""
                        }

                        return isDirectory ? "📁 " : ""
                    } catch {
                        owsFailDebug("failed to check isDirectory for file: \(fileInDirectory) with error: \(error)")
                        return ""
                    }
                }()

                let labelText = "\(fileIcon)\(fileInDirectory.lastPathComponent)"

                return OWSTableItem.disclosureItem(withText: labelText) { [weak self] in
                    let subBrowser = DebugUIFileBrowser(fileURL: fileInDirectory)
                    self?.navigationController?.pushViewController(subBrowser, animated: true)
                }
            }

            let filesSection = OWSTableSection(title: "Dir with \(fileItems.count) files", items: fileItems)
            contents.addSection(filesSection)
        } // end `if isDirectory`

        let attributeItems: [OWSTableItem] = {
            do {
                let attributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: fileURL.path)
                return attributes.map { (fileAttribute: FileAttributeKey, value: Any) in
                    let title = fileAttribute.rawValue.replacingOccurrences(of: "NSFile", with: "")
                    return OWSTableItem(title: "\(title): \(value)") {
                        OWSAlerts.showAlert(title: title, message: "\(value)")
                    }
                }
            } catch {
                owsFailDebug("failed getting attributes for file at path: \(fileURL)")
                return []
            }
        }()
        let attributesSection = OWSTableSection(title: "Attributes", items: attributeItems)
        contents.addSection(attributesSection)

        var managementItems = [
            OWSTableItem.disclosureItem(withText: "✎ Rename") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                let alert = UIAlertController(title: "Rename File",
                                              message: "Will be created in \(strongSelf.fileURL.lastPathComponent)",
                    preferredStyle: .alert)

                alert.addAction(OWSAlerts.cancelAction)
                alert.addAction(UIAlertAction(title: "Rename \(strongSelf.fileURL.lastPathComponent)", style: .default) { _ in
                    guard let textField = alert.textFields?.first else {
                        owsFailDebug("missing text field")
                        return
                    }

                    guard let inputString = textField.text, inputString.count >= 4 else {
                        OWSAlerts.showAlert(title: "new file name missing or less than 4 chars")
                        return
                    }

                    let newURL = strongSelf.fileURL.deletingLastPathComponent().appendingPathComponent(inputString)

                    do {
                        try strongSelf.fileManager.moveItem(at: strongSelf.fileURL, to: newURL)

                        Logger.debug("\(strongSelf) moved \(strongSelf.fileURL) -> \(newURL)")
                        strongSelf.navigationController?.popViewController(animated: true)
                    } catch {
                        owsFailDebug("\(strongSelf) failed to move \(strongSelf.fileURL) -> \(newURL) with error: \(error)")
                    }
                })

                alert.addTextField { textField in
                    textField.placeholder = "New Name"
                    textField.text = strongSelf.fileURL.lastPathComponent
                }

                strongSelf.present(alert, animated: true)
            },

            OWSTableItem.disclosureItem(withText: "➡ Move") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                let fileURL: URL = strongSelf.fileURL
                let filename: String = fileURL.lastPathComponent
                let oldDirectory: URL = fileURL.deletingLastPathComponent()

                let alert = UIAlertController(title: "Moving File: \(filename)",
                                              message: "Currently in: \(oldDirectory)",
                    preferredStyle: .alert)

                alert.addAction(OWSAlerts.cancelAction)
                alert.addAction(UIAlertAction(title: "Moving \(filename)", style: .default) { _ in
                    guard let textField = alert.textFields?.first else {
                        owsFailDebug("missing text field")
                        return
                    }

                    guard let inputString = textField.text, inputString.count >= 4 else {
                        OWSAlerts.showAlert(title: "new file dir missing or less than 4 chars")
                        return
                    }

                    let newURL = URL(fileURLWithPath: inputString).appendingPathComponent(filename)

                    do {
                        try strongSelf.fileManager.moveItem(at: fileURL, to: newURL)

                        Logger.debug("\(strongSelf) moved \(fileURL) -> \(newURL)")
                        strongSelf.navigationController?.popViewController(animated: true)
                    } catch {
                        owsFailDebug("\(strongSelf) failed to move \(fileURL) -> \(newURL) with error: \(error)")
                    }
                })

                alert.addTextField { textField in
                    textField.placeholder = "New Directory"
                    textField.text = oldDirectory.path
                }

                strongSelf.present(alert, animated: true)
            },

            OWSTableItem.disclosureItem(withText: "❌ Delete") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                OWSAlerts.showConfirmationAlert(title: "Delete \(strongSelf.fileURL.path)?") { _ in
                    Logger.debug("deleting file at \(strongSelf.fileURL.path)")
                    do {
                        try strongSelf.fileManager.removeItem(atPath: strongSelf.fileURL.path)
                        strongSelf.navigationController?.popViewController(animated: true)
                    } catch {
                        owsFailDebug("failed to remove item: \(strongSelf.fileURL) with error: \(error)")
                    }
                }
            },

            OWSTableItem.disclosureItem(withText: "📋 Copy Path to Clipboard") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                UIPasteboard.general.string = strongSelf.fileURL.path

                let alert = UIAlertController(title: "Path Copied to Clipboard!",
                                              message: "\(strongSelf.fileURL.path)",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Copy Filename Instead", style: .default) { _ in
                    UIPasteboard.general.string = strongSelf.fileURL.lastPathComponent
                })

                alert.addAction(UIAlertAction(title: "Dismiss", style: .default))

                strongSelf.present(alert, animated: true)
            },

            OWSTableItem.disclosureItem(withText: "🔒 Set File Protection") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                let fileURL = strongSelf.fileURL

                let currentFileProtection: FileProtectionType? = {
                    do {
                        let attributes = try strongSelf.fileManager.attributesOfItem(atPath: fileURL.path)
                        return attributes[FileAttributeKey.protectionKey] as? FileProtectionType
                    } catch {
                        owsFailDebug("failed to get current file protection for file: \(fileURL)")
                        return nil
                    }
                }()

                let actionSheet = UIAlertController(title: "Set file protection level",
                    message: "Currently: \(currentFileProtection?.rawValue ?? "Unknown")",
                    preferredStyle: .actionSheet)

                let protections: [FileProtectionType] = [.none, .complete, .completeUnlessOpen, .completeUntilFirstUserAuthentication]
                protections.forEach { (protection: FileProtectionType) in
                    actionSheet.addAction(UIAlertAction(title: "\(protection.rawValue.replacingOccurrences(of: "NSFile", with: ""))", style: .default) { (_: UIAlertAction) in
                        Logger.debug("chose protection: \(protection) for file: \(fileURL)")
                        let fileAttributes: [FileAttributeKey: Any] = [.protectionKey: protection]
                        do {
                            try strongSelf.fileManager.setAttributes(fileAttributes, ofItemAtPath: strongSelf.fileURL.path)
                            Logger.debug("updated file protection at path:\(fileURL.path) to: \(protection.rawValue)")
                            strongSelf.updateContents()
                        } catch {
                            owsFailDebug("failed to update file protection at path:\(fileURL.path) with error: \(error)")
                        }
                    })
                }
                actionSheet.addAction(OWSAlerts.cancelAction)

                strongSelf.present(actionSheet, animated: true)
            }
        ]

        if isDirectory {
            let createFileItem = OWSTableItem.disclosureItem(withText: "📝 Create File in this Dir") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                let alert = UIAlertController(title: "Name of file",
                                              message: "Will be created in \(strongSelf.fileURL.lastPathComponent)",
                    preferredStyle: .alert)

                alert.addAction(OWSAlerts.cancelAction)
                alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
                    guard let textField = alert.textFields?.first else {
                        owsFailDebug("missing text field")
                        return
                    }

                    guard let inputString = textField.text, inputString.count >= 4 else {
                        OWSAlerts.showAlert(title: "file name missing or less than 4 chars")
                        return
                    }

                    let newPath = strongSelf.fileURL.appendingPathComponent(inputString).path

                    Logger.debug("creating file at \(newPath)")
                    strongSelf.fileManager.createFile(atPath: newPath, contents: nil)

                    strongSelf.updateContents()
                })

                alert.addTextField { textField in
                    textField.placeholder = "File Name"
                }

                strongSelf.present(alert, animated: true)
            }

            managementItems.append(createFileItem)

            let createDirItem = OWSTableItem.disclosureItem(withText: "📁 Create Dir in this Dir") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                let alert = UIAlertController(title: "Name of Dir",
                                              message: "Will be created in \(strongSelf.fileURL.lastPathComponent)",
                    preferredStyle: .alert)

                alert.addAction(OWSAlerts.cancelAction)
                alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
                    guard let textField = alert.textFields?.first else {
                        owsFailDebug("missing text field")
                        return
                    }

                    guard let inputString = textField.text, inputString.count >= 4 else {
                        OWSAlerts.showAlert(title: "dir name missing or less than 4 chars")
                        return
                    }

                    let newPath = strongSelf.fileURL.appendingPathComponent(inputString).path

                    Logger.debug("creating dir at \(newPath)")
                    do {
                        try strongSelf.fileManager.createDirectory(atPath: newPath, withIntermediateDirectories: false)
                        strongSelf.updateContents()
                    } catch {
                        owsFailDebug("Failed to create dir: \(newPath) with error: \(error)")
                    }
                })

                alert.addTextField { textField in
                    textField.placeholder = "Dir Name"
                }

                strongSelf.present(alert, animated: true)
            }
            managementItems.append(createDirItem)

        } else { // if not directory

            let shareItem = OWSTableItem.disclosureItem(withText: "📩 Share") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                AttachmentSharing.showShareUI(for: strongSelf.fileURL)
            }
            managementItems.append(shareItem)
        }

        let fileType = isDirectory ? "Dir" : "File"
        let filesSection = OWSTableSection(title: "\(fileType): \(fileURL.lastPathComponent)", items: managementItems)
        contents.addSection(filesSection)

        contents.title = "\(fileType): \(fileURL)"
        return contents
    }
}
