//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

public struct Tooltip {

    // MARK: Properties

    public let title: String?
    public let message: String?
    public let icon: ThemeIcon?
    public let shouldShowCloseButton: Bool

    /// Which views should be interactive while the tooltip is presented.
    /// Default value is `nil`, meaning only the tooltip itself is interactive.
    public let passthroughViews: [UIView]?

    public enum TapAction {
        case dismiss
        case custom(() -> Void)
    }

    /// Action to perform when tapping the content of the tooltip.
    /// Default value is  `.dismiss`.
    public let tapAction: TapAction?

    // Layout
    public let hSpacing: CGFloat = 12
    public let vSpacing: CGFloat = 0

    public init(
        title: String? = nil,
        message: String? = nil,
        icon: ThemeIcon? = nil,
        shouldShowCloseButton: Bool,
        passthroughViews: [UIView]? = nil,
        tapAction: TapAction = .dismiss
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.shouldShowCloseButton = shouldShowCloseButton
        self.passthroughViews = passthroughViews
        self.tapAction = tapAction
    }

    var attributedTitle: NSAttributedString? {
        guard let title else { return nil }
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.dynamicTypeHeadline,
            .foregroundColor: UIColor.Signal.label,
        ])
    }

    var attributedMessage: NSAttributedString? {
        guard let message else { return nil }
        let textColor = title != nil ? UIColor.Signal.secondaryLabel : UIColor.Signal.label
        return NSAttributedString(string: message, attributes: [
            .font: UIFont.dynamicTypeSubheadline,
            .foregroundColor: textColor,
        ])
    }

    // MARK: Presentation

    public func present(
        from viewController: UIViewController,
        sourceView: UIView,
        sourceRect: CGRect? = nil,
        arrowDirections: UIPopoverArrowDirection
    ) {
        let tooltipViewController = TooltipViewController(tooltip: self, presenter: viewController)
        tooltipViewController.overrideUserInterfaceStyle = viewController.overrideUserInterfaceStyle
        tooltipViewController.modalPresentationStyle = .popover

        guard let presentation = tooltipViewController.popoverPresentationController else {
            owsFailDebug("Missing popoverPresentationController")
            return
        }

        presentation.delegate = tooltipViewController
        presentation.sourceView = sourceView
        if let sourceRect {
            presentation.sourceRect = sourceRect
        }
        presentation.permittedArrowDirections = arrowDirections
        presentation.passthroughViews = self.passthroughViews

        viewController.present(tooltipViewController, animated: true)
    }

    // MARK: - TooltipViewController

    public class TooltipViewController: OWSViewController {

        // MARK: Properties

        private static var vMargins: CGFloat = 13

        let tooltip: Tooltip
        let presenter: UIViewController

        init(tooltip: Tooltip, presenter: UIViewController) {
            self.tooltip = tooltip
            self.presenter = presenter
            super.init()
        }

        private var hStack = UIStackView()

        private lazy var iconImageView: UIImageView? = {
            guard let icon = self.tooltip.icon else { return nil }
            let imageView = UIImageView(image: Theme.iconImage(icon))
            imageView.setCompressionResistanceHigh()
            imageView.setContentHuggingHigh()
            imageView.tintColor = UIColor.Signal.label
            return imageView
        }()

        private lazy var titleLabel: UILabel? = {
            guard let title = self.tooltip.attributedTitle else { return nil }
            let label = UILabel()
            label.attributedText = title
            label.numberOfLines = 0
            label.setContentHuggingHorizontalLow()
            return label
        }()

        private lazy var messageLabel: UILabel? = {
            guard let message = self.tooltip.attributedMessage else { return nil }
            let label = UILabel()
            label.attributedText = message
            label.numberOfLines = 0
            label.setContentHuggingHorizontalLow()
            return label
        }()

        private lazy var closeButton: UIImageView? = {
            guard tooltip.shouldShowCloseButton else { return nil }
            let imageView = UIImageView(image: Theme.iconImage(.buttonX))
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
            imageView.addGestureRecognizer(tapGesture)
            imageView.setCompressionResistanceHigh()
            imageView.setContentHuggingHigh()
            imageView.tintColor = UIColor.Signal.secondaryLabel
            return imageView
        }()

        // MARK: Lifecycle

        public override func viewDidLoad() {
            super.viewDidLoad()
            hStack.axis = .horizontal
            hStack.spacing = self.tooltip.hSpacing
            hStack.alignment = .top
            let vStack = UIStackView()
            vStack.axis = .vertical
            vStack.spacing = self.tooltip.vSpacing

            self.iconImageView.map(hStack.addArrangedSubview(_:))

            hStack.addArrangedSubview(vStack)

            self.titleLabel.map(vStack.addArrangedSubview(_:))
            self.messageLabel.map(vStack.addArrangedSubview(_:))

            self.closeButton.map(hStack.addArrangedSubview(_:))

            self.view.addSubview(hStack)
            hStack.autoCenterInSuperview()
            hStack.layoutMargins = .init(hMargin: 0, vMargin: Self.vMargins)
            hStack.isLayoutMarginsRelativeArrangement = true
            hStack.autoPinEdgesToSuperviewMargins()

            if tooltip.tapAction != nil {
                let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
                self.view.addGestureRecognizer(tapGesture)
            }
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            self.updateContentSize()
        }

        private func updateContentSize() {
            let popoverOuterMargin: CGFloat = 64
            let maxWidth = presenter.view.width - popoverOuterMargin

            var contentWidth: CGFloat = 0

            let titleSize = tooltip.attributedTitle?.size() ?? .zero
            let messageSize = tooltip.attributedMessage?.size() ?? .zero
            let textWidth = max(titleSize.width, messageSize.width)
            contentWidth += textWidth

            if let iconImageView {
                contentWidth += iconImageView.width
                contentWidth += self.tooltip.hSpacing
            }

            if let closeButton {
                contentWidth += closeButton.width
                contentWidth += self.tooltip.hSpacing
            }

            // Controlled by the system
            let popoverHMargin: CGFloat = 16
            contentWidth += popoverHMargin * 2

            if contentWidth >= maxWidth {
                hStack.alignment = .top

                // Let the system decide the size that will fit the max width
                let targetWidth = presenter.view.width - popoverOuterMargin
                let fittingSize = CGSize(
                    width: targetWidth,
                    height: UIView.layoutFittingCompressedSize.height
                )
                let targetHeight = self.view.systemLayoutSizeFitting(
                    fittingSize,
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .defaultLow
                ).height
                self.preferredContentSize = .init(width: UIView.layoutFittingCompressedSize.width, height: targetHeight)
            } else {
                hStack.alignment = .center

                // Manually size the tooltip
                var contentHeight = titleSize.height + messageSize.height
                if tooltip.title != nil && tooltip.message != nil {
                    contentHeight += tooltip.vSpacing
                }

                if let iconImageView {
                    contentHeight = max(iconImageView.height, contentHeight)
                }

                if let closeButton {
                    contentHeight = max(closeButton.height, contentHeight)
                }

                contentHeight += Self.vMargins * 2

                self.preferredContentSize = .init(width: contentWidth, height: contentHeight)
            }
        }

        // MARK: Actions

        @objc
        private func didTap() {
            switch self.tooltip.tapAction {
            case .none:
                break
            case .dismiss:
                self.dismiss(animated: true)
            case .custom(let action):
                action()
            }
        }

        @objc
        func closeTapped() {
            self.dismiss(animated: true)
        }
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension Tooltip.TooltipViewController: UIPopoverPresentationControllerDelegate {
    public func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

// MARK: UIViewController + Tooltips

public extension UIViewController {
    var isTooltipPresented: Bool {
        self.presentedViewController is Tooltip.TooltipViewController
    }

    func dismissTooltip(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard self.isTooltipPresented else {
            return
        }
        self.dismiss(animated: animated, completion: completion)
    }
}
