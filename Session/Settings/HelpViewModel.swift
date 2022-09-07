// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class HelpViewModel: SettingsTableViewModel<NoNav, HelpViewModel.Section, HelpViewModel.Section> {
    // MARK: - Section
    
    public enum Section: SettingSection {
        case report
        case translate
        case feedback
        case faq
        case support
        
        var style: SettingSectionHeaderStyle { .padding }
    }
    
    // MARK: - Content
    
    override var title: String { "HELP_TITLE".localized() }
    
    private var _settingsData: [SectionModel] = []
    public override var settingsData: [SectionModel] { _settingsData }
    
    public override var observableSettingsData: ObservableData { _observableSettingsData }
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    private lazy var _observableSettingsData: ObservableData = ValueObservation
        .trackingConstantRegion { db -> [SectionModel] in
            return [
                SectionModel(
                    model: .report,
                    elements: [
                        SettingInfo(
                            id: .report,
                            title: "HELP_REPORT_BUG_TITLE".localized(),
                            subtitle: "HELP_REPORT_BUG_DESCRIPTION".localized(),
                            action: .rightButtonAction(
                                title: "HELP_REPORT_BUG_ACTION_TITLE".localized(),
                                action: { HelpViewModel.shareLogs(targetView: $0) }
                            )
                        )
                    ]
                ),
                SectionModel(
                    model: .translate,
                    elements: [
                        SettingInfo(
                            id: .translate,
                            title: "HELP_TRANSLATE_TITLE".localized(),
                            action: .trigger(action: {
                                guard let url: URL = URL(string: "https://crowdin.com/project/session-ios") else {
                                    return
                                }
                                
                                UIApplication.shared.open(url)
                            })
                        )
                    ]
                ),
                SectionModel(
                    model: .feedback,
                    elements: [
                        SettingInfo(
                            id: .feedback,
                            title: "HELP_FEEDBACK_TITLE".localized(),
                            action: .trigger(action: {
                                guard let url: URL = URL(string: "https://getsession.org/survey") else {
                                    return
                                }
                                
                                UIApplication.shared.open(url)
                            })
                        )
                    ]
                ),
                SectionModel(
                    model: .faq,
                    elements: [
                        SettingInfo(
                            id: .faq,
                            title: "HELP_FAQ_TITLE".localized(),
                            action: .trigger(action: {
                                guard let url: URL = URL(string: "https://getsession.org/faq") else {
                                    return
                                }
                                
                                UIApplication.shared.open(url)
                            })
                        )
                    ]
                ),
                SectionModel(
                    model: .support,
                    elements: [
                        SettingInfo(
                            id: .support,
                            title: "HELP_SUPPORT_TITLE".localized(),
                            action: .trigger(action: {
                                guard let url: URL = URL(string: "https://sessionapp.zendesk.com/hc/en-us") else {
                                    return
                                }
                                
                                UIApplication.shared.open(url)
                            })
                        )
                    ]
                )
            ]
        }
        .removeDuplicates()
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    public static func shareLogs(
        viewControllerToDismiss: UIViewController? = nil,
        targetView: UIView? = nil,
        onShareComplete: (() -> ())? = nil
    ) {
        let version: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .defaulting(to: "")
        OWSLogger.info("[Version] iOS \(UIDevice.current.systemVersion) \(version)")
        DDLog.flushLog()
        
        let logFilePaths: [String] = AppEnvironment.shared.fileLogger.logFileManager.sortedLogFilePaths
        
        guard
            let latestLogFilePath: String = logFilePaths.first,
            let viewController: UIViewController = CurrentAppContext().frontmostViewController()
        else { return }
        
        let showShareSheet: () -> () = {
            let shareVC = UIActivityViewController(
                activityItems: [ URL(fileURLWithPath: latestLogFilePath) ],
                applicationActivities: nil
            )
            shareVC.completionWithItemsHandler = { _, _, _, _ in onShareComplete?() }
            
            if UIDevice.current.isIPad {
                shareVC.excludedActivityTypes = []
                shareVC.popoverPresentationController?.permittedArrowDirections = (targetView != nil ? [.up] : [])
                shareVC.popoverPresentationController?.sourceView = (targetView ?? viewController.view)
                shareVC.popoverPresentationController?.sourceRect = (targetView ?? viewController.view).bounds
            }
            viewController.present(shareVC, animated: true, completion: nil)
        }
        
        guard let viewControllerToDismiss: UIViewController = viewControllerToDismiss else {
            showShareSheet()
            return
        }

        viewControllerToDismiss.dismiss(animated: true) {
            showShareSheet()
        }
    }
}
