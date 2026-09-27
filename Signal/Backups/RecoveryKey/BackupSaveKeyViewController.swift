//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import SignalServiceKit
import SignalUI
import SwiftUI

class BackupSaveKeyViewController: OWSViewController, OWSNavigationChildController {
    struct BottomButtonConfig {
        enum Style {
            case primary
            case secondary
        }

        let titleText: String
        let style: Style
        let action: (BackupSaveKeyViewController) -> Void
    }

    enum AEPMode {
        /// The user's current AEP, which must only be viewed after device auth.
        case current(AccountEntropyPool, LocalDeviceAuthentication.AuthSuccess)
        /// A new candidate AEP.
        case newCandidate(AccountEntropyPool)

        var aep: AccountEntropyPool {
            switch self {
            case .current(let aep, _): return aep
            case .newCandidate(let aep): return aep
            }
        }

        var displayableAEP: DisplayableAccountEntropyPool {
            aep.forDisplay
        }
    }

    private let aepMode: AEPMode
    private var aepIsCollapsed: Bool
    private let bottomButtonConfigs: [BottomButtonConfig]
    private let displayableAEP: DisplayableAccountEntropyPool

    /// A view that displays an AEP the user is expected to "save".
    ///
    /// - Parameter aepMode
    /// Context on what kind of AEP is being saved.
    /// - Parameter aepStartsCollapsed
    /// Whether or not the displayed AEP should be "collapsed" initially.
    /// - Parameter bottomButtonConfigs
    /// Describes the bottom buttons to be shown below the displayed AEP.
    init(
        aepMode: AEPMode,
        aepStartsCollapsed: Bool,
        bottomButtonConfigs: [BottomButtonConfig],
    ) {
        self.aepMode = aepMode
        self.aepIsCollapsed = aepStartsCollapsed
        self.displayableAEP = DisplayableAccountEntropyPool(aep: aepMode.aep)
        self.bottomButtonConfigs = bottomButtonConfigs

        super.init()

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }

    // MARK: -

    private lazy var aepTextView: AccountEntropyPoolTextView = {
        let textView = AccountEntropyPoolTextView(mode: .display(displayableAEP))
        textView.backgroundColor = .Signal.secondaryGroupedBackground
        return textView
    }()

    /// Overlaid on `aepTextView` while it is collapsed. Un-collapses it when
    /// tapped.
    private lazy var uncollapseAepTextViewButton = FadeUnderlayButton(
        title: OWSLocalizedString(
            "BACKUP_KEY_SEE_FULL_KEY_BUTTON_TITLE",
            comment: "Title for a button that lets the user see their whole Recovery Key, from a preview.",
        ),
        image: .tapHand,
        fadeColor: .Signal.secondaryGroupedBackground,
        onTap: { [weak self] in
            self?.showFullKey()
        },
    )

    /// Accessory buttons shown with the `aepTextView` when it is uncollapsed.
    private lazy var uncollapsedAepTextViewAccessoryButtonStack = UIStackView.verticalButtonStack(
        buttons: [
            // Copy to Clipboard
            UIButton(
                configuration: .smallSecondary(title: OWSLocalizedString(
                    "BACKUP_RECORD_KEY_COPY_TO_CLIPBOARD_BUTTON_TITLE",
                    comment: "Title for a button allowing users to copy their 'Recovery Key' to the clipboard.",
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.copyToClipboardWithConfirmation()
                },
            ),
        ],
        isFullWidthButtons: false,
    )

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        let screenLockUI = AppEnvironment.shared.screenLockUI
        screenLockUI.sensitiveContentDidLoad(inViewController: self)

        view.backgroundColor = .Signal.groupedBackground

        let heroIconView = UIImageView()
        heroIconView.image = .backupsLock
        heroIconView.contentMode = .scaleAspectFit

        let titleText: String
        let subtitleText: String
        switch aepMode {
        case .current:
            titleText = OWSLocalizedString(
                "BACKUP_RECORD_KEY_TITLE",
                comment: "Title for a view allowing users to save their 'Recovery Key'.",
            )
            subtitleText = OWSLocalizedString(
                "BACKUP_RECORD_KEY_SUBTITLE",
                comment: "Subtitle for a view allowing users to save their 'Recovery Key'.",
            )
        case .newCandidate:
            titleText = OWSLocalizedString(
                "BACKUP_RECORD_KEY_NEW_TITLE",
                comment: "Title for a view allowing users to save their newly-created 'Recovery Key', emphasizing that the key is new.",
            )
            subtitleText = OWSLocalizedString(
                "BACKUP_RECORD_KEY_NEW_SUBTITLE",
                comment: "Subtitle for a view allowing users to save their newly-created 'Recovery Key', emphasizing that the key is new.",
            )
        }

        let headlineLabel = UILabel.title1Label(text: titleText)
        let subheadlineLabel = UILabel.explanationTextLabel(text: subtitleText)

        let bottomButtons: [UIButton] = bottomButtonConfigs.map { config in
            return UIButton(
                configuration: {
                    switch config.style {
                    case .primary:
                        return .largePrimary(title: config.titleText)
                    case .secondary:
                        return .largeSecondary(title: config.titleText)
                    }
                }(),
                primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    config.action(self)
                },
            )
        }

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                heroIconView,
                headlineLabel,
                subheadlineLabel,
                aepTextView,
                uncollapsedAepTextViewAccessoryButtonStack,
                .vStretchingSpacer(),
                bottomButtons.enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
        )
        stackView.spacing = 24

        if aepIsCollapsed {
            aepTextView.visibleRowCount = 1

            // Overlay the button on the whole collapsed text view, so any taps on
            // it trigger the button. Note that the button fades out content below
            // its title label.
            //
            // The text view has a corner radius, so clip the button as well.
            aepTextView.addSubview(uncollapseAepTextViewButton)
            aepTextView.clipsToBounds = true
            uncollapseAepTextViewButton.autoPinEdgesToSuperviewEdges()

            // Hide the accessory buttons while collapsed.
            uncollapsedAepTextViewAccessoryButtonStack.alpha = 0
        }
    }

    private func showFullKey() {
        guard aepIsCollapsed else {
            return
        }

        aepIsCollapsed = false

        // Populate the whole key, and re-layout with animation.
        aepTextView.visibleRowCount = aepTextView.rowCount

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            animations: { [self] in
                uncollapseAepTextViewButton.alpha = 0
                uncollapsedAepTextViewAccessoryButtonStack.alpha = 1
                view.layoutIfNeeded()
            },
            completion: { [self] _ in
                uncollapseAepTextViewButton.removeFromSuperview()
            },
        )
    }

    private func copyToClipboardWithConfirmation() {
        let warningSheet = BackupNeverShareRecoveryKeySheet(
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_RECORD_KEY_COPY_WARNING_SHEET_PRIMARY_BUTTON_TITLE",
                    comment: "Title for the primary button in a warning sheet shown before copying the user's 'Recovery Key' to the clipboard, which acknowledges the warning and proceeds with the copy.",
                ),
                action: { [self] sheet in
                    sheet.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        copyToClipboard()
                    }
                },
            ),
            secondaryButton: nil,
        )

        present(warningSheet, animated: true)
    }

    private func copyToClipboard() {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: displayableAEP.displayString]],
            options: [
                // Don't sync the key across devices.
                .localOnly: true,
                // Only keep the key on the pasteboard for a minute.
                .expirationDate: Date().addingTimeInterval(.minute),
            ],
        )

        let toast = ToastController(
            text: OWSLocalizedString(
                "BACKUP_KEY_COPIED_MESSAGE_TOAST",
                comment: "Toast indicating that the user has copied their recovery key.",
            ),
            image: .copy,
        )
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }
}

// MARK: -

/// A button that underlays a fade layer below its content, such that any
/// content below the button's content is obscured.
///
/// Responsive to LTR and RTL layouts.
private class FadeUnderlayButton: UIButton {
    private let fadeView: GradientView

    init(
        title: String,
        image: UIImage,
        fadeColor: UIColor,
        onTap: @escaping () -> Void,
    ) {
        self.fadeView = GradientView(from: fadeColor, to: fadeColor.withAlphaComponent(0))
        self.fadeView.isUserInteractionEnabled = false

        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = image
            .resized(maxDimensionPoints: 20)?
            .withRenderingMode(.alwaysTemplate)
        configuration.imagePadding = 6
        configuration.baseForegroundColor = .Signal.label
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeFootnote.semibold())
        configuration.contentInsets = NSDirectionalEdgeInsets(hMargin: 24, vMargin: 0)
        self.configuration = configuration

        contentHorizontalAlignment = .trailing

        addAction(UIAction(handler: { _ in onTap() }), for: .primaryActionTriggered)

        insertSubview(fadeView, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFade()
    }

    private func updateFade() {
        fadeView.frame = bounds
        let width = bounds.width

        // Get a frame for the image and titleLabel, so the fade covers both.
        var contentFrame = CGRect.null
        if let titleFrame = titleLabel?.frame, titleFrame.width > 0 {
            contentFrame = contentFrame.union(titleFrame)
        }
        if let imageFrame = imageView?.frame, imageFrame.width > 0 {
            contentFrame = contentFrame.union(imageFrame)
        }

        guard
            width > 0,
            !contentFrame.isNull,
            contentFrame.width > 0
        else {
            fadeView.isHidden = true
            return
        }
        fadeView.isHidden = false

        let opaqueWidth: CGFloat = contentFrame.width + 36
        let fadeWidth: CGFloat = 148

        // Layer locations are percentages, so convert points to percentages.
        let opaqueStart = opaqueWidth / width
        let fadeStart = opaqueStart + fadeWidth / width

        // locations must stay within [0, 1], and the fade may extend past.
        let locations = [opaqueStart, fadeStart].map { max(0, min(1, $0)) }

        fadeView.locations = locations
        if CurrentAppContext().isRTL {
            fadeView.setAngle(90)
        } else {
            fadeView.setAngle(270)
        }
    }
}

// MARK: -

#if DEBUG

private extension BackupSaveKeyViewController {
    static func forPreview(
        aepMode: AEPMode,
        aepStartsCollapsed: Bool,
        bottomButtonConfigs: [BottomButtonConfig],
    ) -> BackupSaveKeyViewController {
        return BackupSaveKeyViewController(
            aepMode: aepMode,
            aepStartsCollapsed: aepStartsCollapsed,
            bottomButtonConfigs: bottomButtonConfigs,
        )
    }
}

@available(iOS 17, *)
#Preview("Collapsed") {
    UINavigationController(rootViewController: BackupSaveKeyViewController.forPreview(
        aepMode: .newCandidate(AccountEntropyPool()),
        aepStartsCollapsed: true,
        bottomButtonConfigs: [
            BackupSaveKeyViewController.BottomButtonConfig(
                titleText: "Save to Password Manager",
                style: .primary,
                action: { _ in print("Save to Password Manager!") },
            ),
            BackupSaveKeyViewController.BottomButtonConfig(
                titleText: "Save Manually",
                style: .primary,
                action: { _ in print("Save Manually!") },
            ),
        ],
    ))
}

@available(iOS 17, *)
#Preview("Uncollapsed") {
    UINavigationController(rootViewController: BackupSaveKeyViewController.forPreview(
        aepMode: .newCandidate(AccountEntropyPool()),
        aepStartsCollapsed: false,
        bottomButtonConfigs: [
            BackupSaveKeyViewController.BottomButtonConfig(
                titleText: "Create New Key",
                style: .secondary,
                action: { _ in print("Create New Key!") },
            ),
        ],
    ))
}

#endif
