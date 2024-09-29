//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalUI
import SignalServiceKit

public enum SafetyTipsType {
    case contact
    case group
}

public class SafetyTipsViewController: InteractiveSheetViewController, UIScrollViewDelegate {
    let contentScrollView = UIScrollView()
    let stackView = UIStackView()
    public override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
    public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    private enum Constants {
        static let stackSpacing: CGFloat = 12.0

        static let outerSpacing: CGFloat = 20.0
        static let outerMargins: UIEdgeInsets = .init(hMargin: 24.0, vMargin: 0.0)

        static let footerSpacing: CGFloat = 16.0
        static let footerMargins: UIEdgeInsets = .init(
            top: 0.0,
            left: 24.0,
            bottom: 42.0,
            right: 24.0
        )

        static let buttonInsets: UIEdgeInsets = .init(
            top: 16.0,
            leading: 36.0,
            bottom: 12.0,
            trailing: 36.0
        )

        static let buttonEdgeInsets: UIEdgeInsets = .init(
            hMargin: 0.0,
            vMargin: 14.0
        )
    }

    fileprivate enum SafetyTips: CaseIterable {
        case crypto
        case vagueMessages
        case messagesWithLinks
        case fakeBusiness

        var image: UIImage? {
            switch self {
            case .crypto:
                return UIImage(named: "safety-tip-1")
            case .vagueMessages:
                return UIImage(named: "safety-tip-2")
            case .messagesWithLinks:
                return UIImage(named: "safety-tip-3")
            case .fakeBusiness:
                return UIImage(named: "safety-tip-4")
            }
        }

        var title: String {
            switch self {
            case .crypto:
                return OWSLocalizedString(
                    "SAFETY_TIPS_CRYPTO_TITLE",
                    comment: "Message title describing the crypto safety tip."
                )
            case .vagueMessages:
                return OWSLocalizedString(
                    "SAFETY_TIPS_VAGUE_MESSAGE_TITLE",
                    comment: "Message title describing the safety tip about vague messages."
                )
            case .messagesWithLinks:
                return OWSLocalizedString(
                    "SAFETY_TIPS_MESSAGE_LINKS_TITLE",
                    comment: "Message title describing the safety tip about unknown links in messages."
                )
            case .fakeBusiness:
                return OWSLocalizedString(
                    "SAFETY_TIPS_FAKE_BUSINESS_TITLE",
                    comment: "Message title describing the safety tip about unknown or fake businesses."
                )
            }
        }

        var body: String {
            switch self {
            case .crypto:
                return OWSLocalizedString(
                    "SAFETY_TIPS_CRYPTO_BODY",
                    comment: "Message contents for the crypto safety tip."
                )
            case .vagueMessages:
                return OWSLocalizedString(
                    "SAFETY_TIPS_VAGUE_MESSAGE_BODY",
                    comment: "Message contents for the vague message safety tip."
                )
            case .messagesWithLinks:
                return OWSLocalizedString(
                    "SAFETY_TIPS_MESSAGE_LINKS_BODY",
                    comment: "Message contents for the unknown links in messages safety tip."
                )
            case .fakeBusiness:
                return OWSLocalizedString(
                    "SAFETY_TIPS_FAKE_BUSINESS_BODY",
                    comment: "Message contents for the safety tip concerning fake businesses."
                )
            }
        }
    }

    public var prefersNavigationBarHidden: Bool { true }

    private let type: SafetyTipsType

    init(type: SafetyTipsType) {
        self.type = type
        super.init()
    }

    public override func viewDidLoad() {

        minimizedHeight = min(725, CurrentAppContext().frame.height)
        super.allowsExpansion = false

        contentView.addSubview(contentScrollView)
        contentScrollView.addSubview(stackView)

        stackView.axis = .vertical
        stackView.spacing = Constants.outerSpacing
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoPinWidth(toWidthOf: contentScrollView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.autoPinEdge(.bottom, to: .bottom, of: contentView, withOffset: 0.0, relation: .greaterThanOrEqual)

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.autoPinEdgesToSuperviewEdges()

        buildContents()
        updateButtonState()
        setColorsForCurrentTheme()
        super.viewDidLoad()
    }

    public override func themeDidChange() {
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
        pageControl.numberOfPages = SafetyTips.allCases.count
        pageControl.currentPage = 0
        pageControl.addTarget(self, action: #selector(self.changePage), for: .valueChanged)
        return pageControl
    }()

    private lazy var previousTipButton: OWSFlatButton = {
        let previousButton = OWSFlatButton.insetButton(
            title: OWSLocalizedString(
                "SAFETY_TIPS_PREVIOUS_TIP_BUTTON",
                comment: "Button that will show the previous safety tip."
            ),
            font: .dynamicTypeBodyClamped.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapPrevious))
        previousButton.button.setBackgroundImage(UIImage.image(color: .clear), for: .disabled)
        previousButton.button.setTitleColor(.ows_accentBlue, for: .disabled)
        previousButton.contentEdgeInsets = Constants.buttonEdgeInsets
        return previousButton
    }()

    private lazy var nextTipButton: OWSFlatButton = {
        let nextButton = OWSFlatButton.insetButton(
            title: OWSLocalizedString(
                "SAFETY_TIPS_NEXT_TIP_BUTTON",
                comment: "Button that will show the next safety tip."
            ),
            font: .dynamicTypeBodyClamped.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapNext))
        nextButton.button.setBackgroundImage(UIImage.image(color: .clear), for: .disabled)
        nextButton.button.setTitleColor(.ows_accentBlue, for: .disabled)
        nextButton.contentEdgeInsets = Constants.buttonEdgeInsets
        return nextButton
    }()

    private lazy var footerView: UIView = {
        let stackView = UIStackView(arrangedSubviews: [
            previousTipButton,
            nextTipButton,
        ])
        let container = UIView()
        container.addSubview(stackView)
        container.layoutMargins = Constants.footerMargins
        container.setContentHuggingHigh()

        stackView.axis = .horizontal
        stackView.spacing = Constants.footerSpacing
        stackView.distribution = .fillEqually
        stackView.autoPinEdgesToSuperviewMargins()

        return container
    }()

    // MARK: - TableView

    private func buildContents() {
        prepareTipsScrollView()
        stackView.removeAllSubviews()
        stackView.addArrangedSubview(Self.HeaderView(type: type))
        stackView.addArrangedSubview(tipScrollView)
        stackView.setCustomSpacing(8.0, after: tipScrollView)
        stackView.addArrangedSubview(pageControl)
        stackView.setCustomSpacing(0.0, after: pageControl)
        stackView.addArrangedSubview(UIView.transparentSpacer())
        stackView.addArrangedSubview(footerView)
    }

    private func prepareTipsScrollView() {
        var priorView: UIView?
        tipScrollView.removeAllSubviews()
        SafetyTips.allCases.forEach { tip in
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
            previousTipButton.setEnabled(false)
            nextTipButton.setEnabled(true)
        case pageControl.numberOfPages - 1:
            previousTipButton.setEnabled(true)
            nextTipButton.setEnabled(false)
        default:
            previousTipButton.setEnabled(true)
            nextTipButton.setEnabled(true)
        }
    }

    private func setColorsForCurrentTheme() {
        pageControl.pageIndicatorTintColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray20
        pageControl.currentPageIndicatorTintColor = Theme.isDarkThemeEnabled ? .ows_gray20 : .ows_gray65
    }
}

extension SafetyTipsViewController {
    class HeaderView: UIView {

        private let type: SafetyTipsType

        // MARK: Init

        init(type: SafetyTipsType) {
            self.type = type
            super.init(frame: .zero)
            layoutMargins = Constants.outerMargins

            let stackView = UIStackView()
            self.addSubview(stackView)

            stackView.axis = .vertical
            stackView.alignment = .center
            stackView.spacing = Constants.stackSpacing
            stackView.autoPinEdgesToSuperviewMargins()
            stackView.addArrangedSubviews([
                titleLabel,
                subtitleLabel
            ])

            self.setContentHuggingHigh()
            updateFontsForCurrentPreferredContentSize()
            setColorsForCurrentTheme()
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Views

        private lazy var titleLabel: UILabel = {
            let label = UILabel()
            label.text = OWSLocalizedString(
                "SAFETY_TIPS_HEADER_TITLE",
                comment: "Title for Safety Tips education screen.")
            label.numberOfLines = 0
            label.textAlignment = .center
            label.lineBreakMode = .byWordWrapping
            label.setContentHuggingVerticalHigh()
            return label
        }()

        private lazy var subtitleLabel: UILabel = {
            let label = UILabel()
            let message = {
                switch type {
                case .contact:
                    return OWSLocalizedString(
                        "SAFETY_TIPS_INDIVIDUAL_HEADER_MESSAGE",
                        comment: "Message describing safety tips for 1:1 conversations."
                    )
                case .group:
                    return OWSLocalizedString(
                        "SAFETY_TIPS_GROUPS_HEADER_MESSAGE",
                        comment: "Message describing safety tips for group conversations."
                    )
                }
            }()
            label.text = message
            label.numberOfLines = 0
            label.textAlignment = .center
            label.lineBreakMode = .byWordWrapping
            label.setContentHuggingVerticalHigh()
            return label
        }()

        // MARK: - Style views

        func updateFontsForCurrentPreferredContentSize() {
            titleLabel.font = .dynamicTypeTitle2Clamped.bold()
            subtitleLabel.font = .dynamicTypeBody2Clamped
        }

        func setColorsForCurrentTheme() {
            titleLabel.textColor = Theme.primaryTextColor
            subtitleLabel.textColor = Theme.primaryTextColor
        }
    }
}

extension SafetyTipsViewController {
    class SafetyTipView: UIView {
        private enum Constants {
            static let cornerRadius: CGFloat = 20.0
            static let layoutMargin: CGFloat = 12.0
            static let imageMargin: CGFloat = 24.0
            static let containerMargins: UIEdgeInsets = .init(
                top: layoutMargin,
                left: layoutMargin,
                bottom: 24.0,
                right: layoutMargin
            )
        }

        fileprivate init(safetyTip: SafetyTips) {
            super.init(frame: .zero)
            layoutMargins = .init(hMargin: 24.0, vMargin: 0.0)

            let containerView = UIView()
            containerView.layer.cornerRadius = Constants.cornerRadius
            containerView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_white
            self.addSubview(containerView)
            containerView.layoutMargins = Constants.containerMargins
            containerView.autoPinEdgesToSuperviewMargins()

            let stackView = UIStackView()
            stackView.axis = .vertical
            containerView.addSubview(stackView)
            stackView.spacing = Constants.layoutMargin
            stackView.autoPinEdgesToSuperviewMargins()

            let imageContainerView = UIView()
            imageContainerView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray02
            imageContainerView.layer.cornerRadius = Constants.cornerRadius
            imageContainerView.layoutMargins = .init(margin: Constants.imageMargin)
            stackView.addArrangedSubview(imageContainerView)

            let imageView = UIImageView(image: safetyTip.image)
            imageView.contentMode = .scaleAspectFit

            imageContainerView.addSubview(imageView)
            imageView.autoPinEdgesToSuperviewMargins()
            imageView.autoPinToAspectRatio(withSize: safetyTip.image?.size ?? .init(square: 1.0))

            let titleLabel = UILabel()
            titleLabel.text = safetyTip.title
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .center
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.font = .dynamicTypeBody.bold()
            titleLabel.textColor = Theme.primaryTextColor
            stackView.addArrangedSubview(titleLabel)

            let messageLabel = UILabel()
            messageLabel.text = safetyTip.body
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
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
