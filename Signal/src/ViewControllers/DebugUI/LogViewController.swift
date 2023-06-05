//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class LogPickerViewController: OWSTableViewController2 {
    let logDirUrl: URL

    public init(logDirUrl: URL) {
        self.logDirUrl = logDirUrl
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    public func updateTableContents() {
        let contents = OWSTableContents()
        contents.add(buildPreferenceSection())
        contents.add(buildActionsSection())
        contents.add(buildLogsSection())
        self.contents = contents
    }

    private func buildPreferenceSection() -> OWSTableSection {
        let enableItem = OWSTableItem.switch(withText: "🚂 Play Sound When Errors Occur",
                                             isOn: { Preferences.isAudibleErrorLoggingEnabled},
                                             target: self,
                                             selector: #selector(didToggleAudiblePreference(_:)))
        return OWSTableSection(title: "Preferences", items: [enableItem])
    }

    private func buildActionsSection() -> OWSTableSection {
        let exportItem = OWSTableItem(title: "Export Logs") {
            Logger.flush()
            DebugLogs.exportLogs()
        }
        return OWSTableSection(title: "Actions", items: [exportItem])
    }

    private func buildLogsSection() -> OWSTableSection {
        guard let directoryEnumerator = FileManager.default.enumerator(at: logDirUrl, includingPropertiesForKeys: nil) else {
            owsFailDebug("logUrls was unexpectedly nil")
            return OWSTableSection(title: "No Log URLs", items: [])
        }

        let logUrls: [URL] = directoryEnumerator.compactMap { $0 as? URL }
        let sortedUrls = logUrls.sorted { (a, b) -> Bool in
            return a.lastPathComponent > b.lastPathComponent
        }

        let logItems: [OWSTableItem] = sortedUrls.map { logUrl in
            return OWSTableItem(
                customCellBlock: { () -> UITableViewCell in
                    let cell = OWSTableItem.newCell()
                    guard let textLabel = cell.textLabel else {
                        owsFailDebug("textLabel was unexpectedly nil")
                        return cell
                    }
                    textLabel.lineBreakMode = .byTruncatingHead
                    textLabel.text = logUrl.lastPathComponent

                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    let logVC = LogViewController(logUrl: logUrl)

                    guard let navigationController = self.navigationController else {
                        owsFailDebug("navigationController was unexpectedly nil")
                        return
                    }

                    navigationController.pushViewController(logVC, animated: true)
                }
            )
        }

        return OWSTableSection(title: "View Logs", items: logItems)
    }

    @objc
    private func didToggleAudiblePreference(_ sender: UISwitch) {
        Preferences.setIsAudibleErrorLoggingEnabled(sender.isOn)
        if sender.isOn {
            ErrorLogger.playAlertSound()
        }
    }
}

public class LogViewController: UIViewController {

    let logUrl: URL

    public init(logUrl: URL) {
        self.logUrl = logUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let textView = UITextView()

    override public func loadView() {
        self.view = textView
        loadLogText()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .action,
                                                              target: self,
                                                              action: #selector(didTapShare(_:))),
                                              UIBarButtonItem(barButtonSystemItem: .trash,
                                                              target: self,
                                                              action: #selector(didTapTrash(_:)))]
    }

    func loadLogText() {
        do {
            // This is super crude, but:
            // 1. generally we should haven't a ton of logged errors
            // 2. this is a dev tool
            let logData = try Data(contentsOf: logUrl)

            // TODO most recent lines on top?
            textView.text = String(data: logData, encoding: .utf8)
        } catch {
            textView.text = "Failed to load log data: \(error)"
        }
    }

    @objc
    private func didTapTrash(_ sender: UIBarButtonItem) {
        // truncate logUrl
        do {
            try NSData().write(to: logUrl)
            loadLogText()
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    @objc
    private func didTapShare(_ sender: UIBarButtonItem) {
        let logText = textView.text ?? "Empty Log"
        let vc = UIActivityViewController(activityItems: [logText], applicationActivities: [])
        present(vc, animated: true)
    }
}
