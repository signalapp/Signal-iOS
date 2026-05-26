//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

public enum SafetyTipsType {
    case contact
    case group
}

public class SafetyTipsViewController: InteractiveSheetViewController, UIScrollViewDelegate {
    public struct Button {
        let title: String
        let action: () -> Void
    }

    override public var placeOnGlassIfAvailable: Bool { true }
    let primaryButton: Button

    init(primaryButton: Button) {
        self.primaryButton = primaryButton
    }

    private enum SafetyTips: CaseIterable {
        case chatsFromSignal
        case reviewNames
        case scams

        var image: UIImage? {
            switch self {
            case .chatsFromSignal:
                return UIImage(resource: .safetytip4801)
            case .reviewNames:
                return UIImage(resource: .safetytip4802)
            case .scams:
                return UIImage(resource: .safetytip4803)
            }
        }

        var title: String {
            switch self {
            case .chatsFromSignal:
                return OWSLocalizedString(
                    "SAFETY_TIPS_SIGNAL_CHATS_TITLE",
                    comment: "Message title describing the signal chats tip.",
                )
            case .reviewNames:
                return OWSLocalizedString(
                    "SAFETY_TIPS_REVIEW_NAMES_TITLE",
                    comment: "Message title describing the review names safety tip.",
                )
            case .scams:
                return OWSLocalizedString(
                    "SAFETY_TIPS_LOOK_OUT_FOR_SCAMS_TITLE",
                    comment: "Message title describing the scams safety tip.",
                )
            }
        }

        var body: String {
            switch self {
            case .chatsFromSignal:
                return OWSLocalizedString(
                    "SAFETY_TIPS_SIGNAL_CHATS_BODY",
                    comment: "Message body describing the signal chats tip.",
                )
            case .reviewNames:
                return OWSLocalizedString(
                    "SAFETY_TIPS_REVIEW_NAMES_BODY",
                    comment: "Message body describing the review names safety tip.",
                )
            case .scams:
                return OWSLocalizedString(
                    "SAFETY_TIPS_LOOK_OUT_FOR_SCAMS_BODY",
                    comment: "Message body describing the scams safety tip.",
                )
            }
        }
    }

    let contentScrollView = UIScrollView()
    let stackView = UIStackView()

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = min(612, CurrentAppContext().frame.height)
        super.allowsExpansion = false

        let header = UILabel()
        header.text = OWSLocalizedString(
            "SAFETY_TIPS_HEADER_TITLE",
            comment: "Title for Safety Tips education screen.",
        )
        header.font = .dynamicTypeHeadline
        header.textAlignment = .center
        header.isAccessibilityElement = true
        header.accessibilityTraits.insert(.header)
        contentView.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            header.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])

        contentView.addSubview(contentScrollView)
        contentScrollView.addSubview(stackView)

        stackView.axis = .vertical
        stackView.spacing = 20

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            contentScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -90),
            contentScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.trailingAnchor, constant: 24),
            stackView.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor, constant: -48),
        ])

        for bullet in SafetyTips.allCases {
            let bulletView = SafetyBulletView(bullet)
            stackView.addArrangedSubview(bulletView)
        }

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.Signal.secondaryFill
        config.cornerStyle = .capsule
        var attrString = AttributedString(primaryButton.title)
        attrString.font = .dynamicTypeBodyClamped.medium()
        config.attributedTitle = attrString
        config.baseForegroundColor = UIColor.Signal.label
        config.contentInsets = .init(margin: 14)
        let button = UIButton(
            configuration: config,
            primaryAction: .init(handler: { [weak self] _ in
                self?.dismiss(animated: true, completion: {
                    self?.primaryButton.action()
                })
            }),
        )

        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            button.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private class SafetyBulletView: UIStackView {
        init(_ bullet: SafetyTips) {
            super.init(frame: .zero)

            self.axis = .horizontal
            self.alignment = .firstBaseline
            self.spacing = 24
            self.isLayoutMarginsRelativeArrangement = true
            self.layoutMargins = .zero

            let textStack = UIStackView()
            textStack.axis = .vertical
            textStack.spacing = 8

            let headerLabel = UILabel()
            headerLabel.text = bullet.title
            headerLabel.numberOfLines = 0
            headerLabel.textColor = UIColor.Signal.label
            headerLabel.font = .dynamicTypeBody.semibold()
            textStack.addArrangedSubview(headerLabel)

            let bodyLabel = UILabel()
            bodyLabel.text = bullet.body
            bodyLabel.numberOfLines = 0
            bodyLabel.textColor = UIColor.Signal.secondaryLabel
            bodyLabel.font = .dynamicTypeBody
            textStack.addArrangedSubview(bodyLabel)

            let bulletPoint = UIImageView(image: bullet.image)
            bulletPoint.contentMode = .scaleAspectFit
            bulletPoint.translatesAutoresizingMaskIntoConstraints = false
            bulletPoint.widthAnchor.constraint(equalToConstant: 48).isActive = true
            bulletPoint.heightAnchor.constraint(equalToConstant: 48).isActive = true

            addArrangedSubview(bulletPoint)
            addArrangedSubview(textStack)
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

public class MoreSafetyTipsViewController: InteractiveSheetViewController, UIScrollViewDelegate {
    override public var placeOnGlassIfAvailable: Bool { true }

    let contentScrollView = UIScrollView()
    override public var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
    override public var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    private enum Constants {
        static let stackSpacing: CGFloat = 12.0

        static let outerSpacing: CGFloat = 20.0
        static let outerMargins: UIEdgeInsets = .init(hMargin: 24.0, vMargin: 0.0)

        static let footerSpacing: CGFloat = 16.0

        static let buttonDiameter: CGFloat = 52.0
        static let buttonMargin: CGFloat = 24.0
    }

    fileprivate enum MoreSafetyTips: CaseIterable {
        case chatsFromSignal
        case reviewNames
        case vagueMessages
        case messagesWithLinks
        case crypto
        case fakeBusiness

        var image: UIImage? {
            switch self {
            case .chatsFromSignal:
                return UIImage(resource: .safetytip24001)
            case .reviewNames:
                return UIImage(resource: .safetytip24002)
            case .vagueMessages:
                return UIImage(resource: .safetytip24003)
            case .messagesWithLinks:
                return UIImage(resource: .safetytip24004)
            case .crypto:
                return UIImage(resource: .safetytip24005)
            case .fakeBusiness:
                return UIImage(resource: .safetytip24006)
            }
        }

        var title: String {
            switch self {
            case .chatsFromSignal:
                return OWSLocalizedString(
                    "SAFETY_TIPS_SIGNAL_CHATS_TITLE",
                    comment: "Message title describing the signal chats tip.",
                )
            case .reviewNames:
                return OWSLocalizedString(
                    "SAFETY_TIPS_REVIEW_NAMES_TITLE",
                    comment: "Message title describing the review names safety tip.",
                )
            case .vagueMessages:
                return OWSLocalizedString(
                    "SAFETY_TIPS_VAGUE_MESSAGE_TITLE",
                    comment: "Message title describing the safety tip about vague messages.",
                )
            case .messagesWithLinks:
                return OWSLocalizedString(
                    "SAFETY_TIPS_MESSAGE_LINKS_TITLE",
                    comment: "Message title describing the safety tip about unknown links in messages.",
                )
            case .crypto:
                return OWSLocalizedString(
                    "SAFETY_TIPS_CRYPTO_TITLE",
                    comment: "Message title describing the crypto safety tip.",
                )
            case .fakeBusiness:
                return OWSLocalizedString(
                    "SAFETY_TIPS_FAKE_BUSINESS_TITLE",
                    comment: "Message title describing the safety tip about unknown or fake businesses.",
                )
            }
        }

        var body: String {
            switch self {
            case .chatsFromSignal:
                return OWSLocalizedString(
                    "SAFETY_TIPS_SIGNAL_CHATS_BODY_VIEW_MORE",
                    comment: "Message body describing the signal chats tip in the 'view more' flow.",
                )
            case .reviewNames:
                return OWSLocalizedString(
                    "SAFETY_TIPS_REVIEW_NAMES_BODY_VIEW_MORE",
                    comment: "Message body describing the review names safety tip in the 'view more' flow.",
                )
            case .vagueMessages:
                return OWSLocalizedString(
                    "SAFETY_TIPS_VAGUE_MESSAGE_BODY",
                    comment: "Message contents for the vague message safety tip.",
                )
            case .messagesWithLinks:
                return OWSLocalizedString(
                    "SAFETY_TIPS_MESSAGE_LINKS_BODY",
                    comment: "Message contents for the unknown links in messages safety tip.",
                )
            case .crypto:
                return OWSLocalizedString(
                    "SAFETY_TIPS_CRYPTO_BODY",
                    comment: "Message contents for the crypto safety tip.",
                )
            case .fakeBusiness:
                return OWSLocalizedString(
                    "SAFETY_TIPS_FAKE_BUSINESS_BODY",
                    comment: "Message contents for the safety tip concerning fake businesses.",
                )
            }
        }
    }

    var prefersNavigationBarHidden: Bool { true }

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = min(510, CurrentAppContext().frame.height)
        super.allowsExpansion = false

        contentView.addSubview(contentScrollView)
        contentScrollView.addSubview(tipScrollView)

        tipScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tipScrollView.topAnchor.constraint(equalTo: contentScrollView.topAnchor),
            tipScrollView.bottomAnchor.constraint(equalTo: contentScrollView.bottomAnchor),
            tipScrollView.leadingAnchor.constraint(equalTo: contentScrollView.leadingAnchor),
            tipScrollView.trailingAnchor.constraint(equalTo: contentScrollView.trailingAnchor),
            tipScrollView.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor),
        ])

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -84),
            contentScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentScrollView.widthAnchor.constraint(equalTo: contentView.widthAnchor),
        ])

        buildContents()
        updateButtonState()
        setColorsForCurrentTheme()
    }

    override public func themeDidChange() {
        super.themeDidChange()
        buildContents()
        updateButtonState()
        setColorsForCurrentTheme()
    }

    // MARK: - Views

    private lazy var tipScrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: .zero)
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        return scrollView
    }()

    private lazy var pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.numberOfPages = MoreSafetyTips.allCases.count
        pageControl.currentPage = 0
        pageControl.addTarget(self, action: #selector(self.changePage), for: .valueChanged)
        return pageControl
    }()

    private lazy var previousTipButton: UIButton = {
        let previousButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.baseForegroundColor = UIColor.Signal.label
        config.baseBackgroundColor = UIColor.Signal.primaryFill
        config.image = UIImage(resource: .chevronLeft26)
        config.cornerStyle = .capsule
        previousButton.accessibilityLabel = CommonStrings.backButton
        previousButton.configuration = config
        previousButton.addTarget(self, action: #selector(didTapPrevious), for: .touchUpInside)

        return previousButton

    }()

    private lazy var nextTipButton: UIButton = {
        let nextButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.baseForegroundColor = UIColor.Signal.label
        config.baseBackgroundColor = UIColor.Signal.primaryFill
        config.image = UIImage(resource: .chevronRight26)
        config.cornerStyle = .capsule
        nextButton.configuration = config
        nextButton.accessibilityLabel = CommonStrings.nextButton
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        return nextButton
    }()

    private lazy var footerView: UIView = {
        let stackView = UIStackView(arrangedSubviews: [
            previousTipButton,
            pageControl,
            nextTipButton,
        ])

        nextTipButton.translatesAutoresizingMaskIntoConstraints = false
        previousTipButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nextTipButton.widthAnchor.constraint(equalToConstant: Constants.buttonDiameter),
            nextTipButton.heightAnchor.constraint(equalToConstant: Constants.buttonDiameter),
            previousTipButton.widthAnchor.constraint(equalToConstant: Constants.buttonDiameter),
            previousTipButton.heightAnchor.constraint(equalToConstant: Constants.buttonDiameter),
        ])

        let container = UIView()
        container.addSubview(stackView)

        stackView.axis = .horizontal
        stackView.spacing = Constants.footerSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.buttonMargin),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.buttonMargin),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.buttonMargin),
        ])

        return container
    }()

    // MARK: - TableView

    private func buildContents() {
        prepareTipsScrollView()

        contentView.addSubview(footerView)
        footerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 84),
        ])
    }

    private func prepareTipsScrollView() {
        var priorView: UIView?
        tipScrollView.removeAllSubviews()
        MoreSafetyTips.allCases.forEach { tip in
            let view = SafetyTipView(safetyTip: tip)
            tipScrollView.addSubview(view)

            view.autoPinHeight(toHeightOf: tipScrollView)
            view.autoPinWidth(toWidthOf: tipScrollView)
            if let priorView {
                view.autoPinEdge(.leading, to: .trailing, of: priorView)
            } else {
                view.autoPinEdge(.leading, to: .leading, of: tipScrollView)
            }
            priorView = view
        }
        priorView?.autoPinEdge(.trailing, to: .trailing, of: tipScrollView)
    }

    // MARK: - ScrollViewDelegate

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageNumber = round(scrollView.contentOffset.x / scrollView.frame.size.width)
        pageControl.currentPage = Int(pageNumber)
        updateButtonState()
    }

    // MARK: - Actions

    @objc
    private func changePage() {
        let x = CGFloat(pageControl.currentPage) * tipScrollView.frame.size.width
        tipScrollView.setContentOffset(CGPoint(x: x, y: 0), animated: true)
        updateButtonState()

        let currentPageView = tipScrollView.subviews[pageControl.currentPage]
        DispatchQueue.main.async {
            UIAccessibility.post(notification: .layoutChanged, argument: currentPageView)
        }
    }

    @objc
    private func didTapPrevious() {
        pageControl.currentPage = max(pageControl.currentPage - 1, 0)
        changePage()
    }

    @objc
    private func didTapNext() {
        pageControl.currentPage = min(pageControl.currentPage + 1, pageControl.numberOfPages)
        changePage()
    }

    private func updateButtonState() {
        switch pageControl.currentPage {
        case 0:
            // hide previous, show next
            previousTipButton.alpha = 0
            previousTipButton.isUserInteractionEnabled = false
            nextTipButton.alpha = 1
            nextTipButton.isUserInteractionEnabled = true
        case pageControl.numberOfPages - 1:
            // show previous, hide next
            previousTipButton.alpha = 1
            previousTipButton.isUserInteractionEnabled = true
            nextTipButton.alpha = 0
            nextTipButton.isUserInteractionEnabled = false
        default:
            // show previous, show next
            previousTipButton.alpha = 1
            previousTipButton.isUserInteractionEnabled = true
            nextTipButton.alpha = 1
            nextTipButton.isUserInteractionEnabled = true
        }
    }

    private func setColorsForCurrentTheme() {
        pageControl.pageIndicatorTintColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray20
        pageControl.currentPageIndicatorTintColor = Theme.isDarkThemeEnabled ? .ows_gray20 : .ows_gray65
    }
}

extension MoreSafetyTipsViewController {
    class SafetyTipView: UIView {
        fileprivate init(safetyTip: MoreSafetyTips) {
            super.init(frame: .zero)
            layoutMargins = .init(hMargin: 24.0, vMargin: 0.0)

            let stackView = UIStackView()
            stackView.axis = .vertical
            self.addSubview(stackView)
            stackView.spacing = 8.0

            stackView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 16),
                stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                stackView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor),
            ])

            let imageView = UIImageView(image: safetyTip.image)
            imageView.contentMode = .scaleAspectFit

            stackView.addArrangedSubview(imageView)
            stackView.addArrangedSubview(SpacerView(preferredHeight: 10.0))

            NSLayoutConstraint.activate([
                imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 160),
            ])

            let titleLabel = UILabel()
            titleLabel.text = safetyTip.title
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .left
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.font = .dynamicTypeBody.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            stackView.addArrangedSubview(titleLabel)

            let messageLabel = UILabel()
            messageLabel.text = safetyTip.body
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .left
            messageLabel.lineBreakMode = .byWordWrapping
            messageLabel.font = .dynamicTypeBodyClamped
            messageLabel.textColor = Theme.secondaryTextAndIconColor
            stackView.addArrangedSubview(messageLabel)
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
