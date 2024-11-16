//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit
import SignalUI
import UIKit

@MainActor
struct DoubleTapToEditOnboardingController {
    private enum Keys {
        public static let collectionIdentifier = "DoubleTapToEdit"
        public static let hasSeenOnboarding = "hasSeenOnboarding"
    }

    private var completionHandler: @MainActor () -> Void
    private var presentationContext: UIViewController

    init(presentationContext: UIViewController, completionHandler: @MainActor @escaping () -> Void) {
        self.completionHandler = completionHandler
        self.presentationContext = presentationContext
    }

    func beginEditing(animated: Bool) {
        let store = KeyValueStore(collection: Keys.collectionIdentifier)
        let db = DependenciesBridge.shared.db
        let hasSeenOnboarding = db.read { store.getBool(Keys.hasSeenOnboarding, defaultValue: false, transaction: $0) }

        if hasSeenOnboarding {
            completionHandler()
        } else {
            let sheet = ActionSheetController()
            sheet.customHeader = HeaderView()
            sheet.addAction(.acknowledge)
            sheet.onDismiss = {
                db.asyncWrite { store.setBool(true, key: Keys.hasSeenOnboarding, transaction: $0) }
                MainActor.assumeIsolated {
                    completionHandler()
                }
            }
            presentationContext.present(sheet, animated: animated)
        }
    }
}

private extension DoubleTapToEditOnboardingController {
    final class HeaderView: UIView {
        private let stack: UIStackView
        private let imageView: UIImageView
        private let title: UILabel
        private let message: UILabel

        override init(frame: CGRect) {
            imageView = UIImageView(image: UIImage(named: "tap-hand"))
            imageView.setContentCompressionResistancePriority(.required, for: .vertical)

            title = UILabel()
            title.font = .dynamicTypeHeadline
            title.setContentCompressionResistancePriority(.required, for: .vertical)
            title.text = OWSLocalizedString("DOUBLE_TAP_TO_EDIT_ALERT_TITLE", comment: "Title for Double Tap to Edit sheet show on first interaction")

            message = UILabel()
            message.textAlignment = .center
            message.numberOfLines = 0
            message.setContentCompressionResistancePriority(.required, for: .vertical)
            message.text = OWSLocalizedString("DOUBLE_TAP_TO_EDIT_ALERT_MESSAGE", comment: "Message for Double Tap to Edit sheet show on first interaction")

            stack = UIStackView(arrangedSubviews: [imageView, title, message])
            stack.alignment = .center
            stack.axis = .vertical
            stack.isLayoutMarginsRelativeArrangement = true
            stack.preservesSuperviewLayoutMargins = true
            stack.spacing = UIStackView.spacingUseSystem
            stack.translatesAutoresizingMaskIntoConstraints = false

            super.init(frame: frame)
            directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
            addSubview(stack)
            stack.autoPinEdgesToSuperviewEdges()
        }

        required init?(coder: NSCoder) {
            fatalError("not implemented")
        }
    }
}
