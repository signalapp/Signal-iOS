//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

extension DeleteForMeSyncMessage {
    final class InfoSheet: InteractiveSheetViewController {
        private let onConfirmBlock: () -> Void

        init(onConfirmBlock: @escaping () -> Void) {
            self.onConfirmBlock = onConfirmBlock
        }

        override var interactiveScrollViews: [UIScrollView] { [contentScrollWrapper] }

        private lazy var contentScrollWrapper: UIScrollView = {
            let scrollView = UIScrollView(forAutoLayout: ())
            scrollView.addSubview(_contentView)

            // Pin height to scrollable area, but width to the viewport.
            _contentView.autoPinHeightToSuperview()
            _contentView.autoPinWidth(toWidthOf: scrollView)

            return scrollView
        }()

        private lazy var _contentView: UIView = {
            let view = UIView()

            let headerImageView = { () -> UIImageView in
                let imageName = Theme.isDarkThemeEnabled ? "delete-sync-dark" : "delete-sync-light"
                let imageView = UIImageView(image: UIImage(named: imageName)!)
                imageView.heightAnchor.constraint(equalToConstant: 88).isActive = true
                imageView.contentMode = .scaleAspectFit

                return imageView
            }()

            let titleLabel = { () -> UILabel in
                let label = UILabel()
                label.translatesAutoresizingMaskIntoConstraints = false
                label.text = OWSLocalizedString(
                    "DELETE_FOR_ME_SYNC_MESSAGE_INFO_SHEET_TITLE",
                    comment: "Title for an info sheet explaining that deletes are now synced across devices."
                )
                label.font = .dynamicTypeTitle3.semibold()
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.textAlignment = .center

                return label
            }()

            let subtitleLabel = { () -> UILabel in
                let label = UILabel()
                label.translatesAutoresizingMaskIntoConstraints = false
                label.text = OWSLocalizedString(
                    "DELETE_FOR_ME_SYNC_MESSAGE_INFO_SHEET_SUBTITLE",
                    comment: "Subtitle for an info sheet explaining that deletes are now synced across devices."
                )
                label.font = .dynamicTypeBody
                label.textColor = Theme.isDarkThemeEnabled ? .ows_gray20 : .ows_gray60
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.textAlignment = .center

                return label
            }()

            let spacer = UIView(forAutoLayout: ())

            let gotItButton = { () -> UIButton in
                let button = OWSButton(
                    title: OWSLocalizedString(
                        "DELETE_FOR_ME_SYNC_MESSAGE_INFO_SHEET_BUTTON",
                        comment: "Label for a button in an info sheet confirming that deletes are now synced across devices."
                    ),
                    block: { [weak self] in
                        guard let self else { return }
                        self.dismiss(animated: true) {
                            self.onConfirmBlock()
                        }
                    }
                )
                button.backgroundColor = .ows_accentBlue
                button.layer.cornerRadius = 12
                button.configureForMultilineTitle()
                button.titleLabel!.font = .dynamicTypeHeadline.semibold()

                return button
            }()

            view.addSubview(headerImageView)
            view.addSubview(titleLabel)
            view.addSubview(subtitleLabel)
            view.addSubview(spacer)
            view.addSubview(gotItButton)

            headerImageView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

            titleLabel.autoPinEdge(.top, to: .bottom, of: headerImageView, withOffset: 24)
            titleLabel.autoPinWidthToSuperviewMargins(withInset: 24)

            subtitleLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 12)
            subtitleLabel.autoPinWidthToSuperviewMargins(withInset: 24)

            spacer.autoPinEdge(.top, to: .bottom, of: subtitleLabel)
            spacer.autoPinWidthToSuperviewMargins()
            spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true

            gotItButton.autoPinEdge(.top, to: .bottom, of: spacer)
            gotItButton.autoPinLeadingToSuperviewMargin(withInset: 48)
            gotItButton.autoPinTrailingToSuperviewMargin(withInset: 48)
            gotItButton.autoPinBottomToSuperviewMargin()
            gotItButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

            return view
        }()

        override public func viewDidLoad() {
            super.viewDidLoad()
            minimizedHeight = 487
            allowsExpansion = true

            contentView.addSubview(contentScrollWrapper)
            contentScrollWrapper.autoPinEdgesToSuperviewMargins()
            contentScrollWrapper.alwaysBounceVertical = true
        }
    }
}
