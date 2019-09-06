//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class LogPickerViewController: OWSTableViewController {
    let logDirUrl: URL

    @objc
    public init(logDirUrl: URL) {
        self.logDirUrl = logDirUrl
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    public func updateTableContents() {
        let contents = OWSTableContents()
        contents.addSection(buildPreferenceSection())
        contents.addSection(buildLogsSection())
        self.contents = contents
    }

    private func buildPreferenceSection() -> OWSTableSection {
        let enableItem = OWSTableItem.switch(withText: "🚂 Play Sound When Errors Occur",
                                             isOn: { OWSPreferences.isAudibleErrorLoggingEnabled() },
                                             target: self,
                                             selector: #selector(didToggleAudiblePreference(_:)))
        return OWSTableSection(title: "Preferences", items: [enableItem])
    }

    private func buildLogsSection() -> OWSTableSection {
        guard let logUrls = FileManager.default.enumerator(at: logDirUrl, includingPropertiesForKeys: nil) else {
            owsFailDebug("logUrls was unexpectedly nil")
            return OWSTableSection(title: "No Log URLs", items: [])
        }

        var logItems: [OWSTableItem] = []
        for case let logUrl as URL in logUrls {
            logItems.append(OWSTableItem(title: logUrl.lastPathComponent) { [weak self] in
                guard let self = self else { return }
                let logVC = LogViewController(logUrl: logUrl)

                guard let navigationController = self.navigationController else {
                    owsFailDebug("navigationController was unexpectedly nil")
                    return
                }

                navigationController.pushViewController(logVC, animated: true)
            })
        }

        return OWSTableSection(title: "Error Logs", items: logItems)
    }

    @objc
    func didToggleAudiblePreference(_ sender: UISwitch) {
        OWSPreferences.setIsAudibleErrorLoggingEnabled(sender.isOn)
        if sender.isOn {
            ErrorLogger.playAlertSound()
        }
    }
}

@objc
public class LogViewController: UIViewController {

    let logUrl: URL

    @objc
    public init(logUrl: URL) {
        self.logUrl = logUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let textView = UITextView()
        self.view = textView

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
}
