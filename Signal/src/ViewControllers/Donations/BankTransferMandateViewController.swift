//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging

@MainActor
class BankTransferMandateViewController: OWSTableViewController2 {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    override var navbarBackgroundColorOverride: UIColor? { self.tableBackgroundColor }

    private enum State {
        case loading
        case loaded(mandateText: String)
        case failed
    }

    private var state: State = .loading {
        didSet {
            AssertIsOnMainThread()
            updateTableContents()
            updateBottomFooter()
        }
    }

    private var bankTransferType: OWSRequestFactory.StripePaymentMethod.BankTransfer
    private var didAgree: (Stripe.PaymentMethod.Mandate) -> Void

    init(
        bankTransferType: OWSRequestFactory.StripePaymentMethod.BankTransfer,
        didAgree: @escaping (Stripe.PaymentMethod.Mandate) -> Void
    ) {
        self.bankTransferType = bankTransferType
        self.didAgree = didAgree
        super.init()
    }

    // MARK: Table setup

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        updateTableContents()
        updateBottomFooter()

        Task {
            await loadMandate()
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
        updateBottomFooter()
    }

    private func updateTableContents() {
        let section = OWSTableSection(header: self.makeHeaderView)

        switch state {
        case .loading, .failed:
            // TODO: Show a different state if the loading failed
            section.customFooterView = Self.makeLoadingview()
        case .loaded(let mandateText):
            section.add(Self.makeBodyLabelCell(text: mandateText))
        }

        section.shouldDisableCellSelection = true

        self.contents = OWSTableContents(sections: [section])
    }

    private static let bankIconSize: CGFloat = 40
    private static let bankIconContainerSize: CGFloat = 64
    /// This URL itself is not used. The action is overridden in the text view delegate function.
    private static let learnMoreURL = URL(string: "https://support.signal.org/")!

    private func makeHeaderView() -> UIView {
        let bankIcon = UIImage(systemName: "building.columns")
        let bankIconView = UIImageView(image: bankIcon)
        bankIconView.contentMode = .scaleAspectFit
        bankIconView.tintColor = Theme.primaryTextColor
        bankIconView.autoSetDimensions(to: .square(Self.bankIconSize))

        let bankIconContainer = UIView()
        bankIconContainer.backgroundColor = self.cellBackgroundColor
        bankIconContainer.autoSetDimensions(to: .square(Self.bankIconContainerSize))
        bankIconContainer.layer.cornerRadius = Self.bankIconContainerSize / 2
        bankIconContainer.addSubview(bankIconView)
        bankIconView.autoCenterInSuperview()

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "BANK_MANDATE_TITLE",
            comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is the title above that mandate."
        )
        titleLabel.font = .dynamicTypeTitle1.semibold()
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let subtitleTextView = LinkingTextView()
        subtitleTextView.delegate = self
        subtitleTextView.attributedText = .composed(of: [
            OWSLocalizedString(
                "BANK_MANDATE_SUBTITLE",
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a subtitle about the payment processor Stripe above that mandate."
            ),
            " ",
            CommonStrings.learnMore.styled(with: .link(Self.learnMoreURL))
        ]).styled(with: .color(Theme.secondaryTextAndIconColor), .font(.dynamicTypeSubheadline))
        subtitleTextView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
        ]
        subtitleTextView.textAlignment = .center

        let stackView = UIStackView(arrangedSubviews: [
            bankIconContainer,
            titleLabel,
            subtitleTextView,
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.setCustomSpacing(12, after: bankIconContainer)

        let container = UIView()
        let hPadding = UIDevice.current.isNarrowerThanIPhone6 ? Self.defaultHOuterMargin : 29
        container.layoutMargins = .init(
            top: 0,
            leading: hPadding,
            bottom: 20,
            trailing: hPadding
        )

        container.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        return container
    }

    private static func makeLoadingview() -> UIActivityIndicatorView {
        let result = UIActivityIndicatorView(style: .medium)
        result.startAnimating()
        return result
    }

    private static func makeBodyLabelCell(text: String) -> OWSTableItem {
        .init(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let label = UILabel()
            label.text = text
            label.font = .dynamicTypeSubheadline
            label.numberOfLines = 0

            cell.contentView.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()

            return cell
        })
    }

    // MARK: Bottom footer

    /// `true` if `tableView` is within 52 points of the bottom, otherwise `false`.
    private var isScrolledCloseToBottom = true {
        didSet {
            if isScrolledCloseToBottom != oldValue {
                updateBottomFooterButtonText()
            }
        }
    }

    private func checkScrollPosition() {
        let tableViewBottom = tableView.contentSize.height - tableView.height
        isScrolledCloseToBottom = tableView.contentOffset.y >= tableViewBottom - 56
    }

    override var bottomFooter: UIView? {
        get { bottomFooterContainer }
        set {}
    }

    private lazy var bottomFooterButton: OWSButton = {
        let button = OWSButton { [weak self] in
            self?.didTapBottomFooterButton()
        }
        button.dimsWhenHighlighted = true
        button.dimsWhenDisabled = true
        button.layer.cornerRadius = 12
        button.backgroundColor = .ows_accentBlue
        button.titleLabel?.font = .dynamicTypeHeadline
        button.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        return button
    }()

    private lazy var bottomFooterContainer: UIView = {
        let view = UIView()
        view.layoutMargins = .init(margin: 20)
        view.addSubview(bottomFooterButton)
        bottomFooterButton.autoPinEdgesToSuperviewMargins()
        return view
    }()

    private func updateBottomFooter() {
        bottomFooterContainer.backgroundColor = self.tableBackgroundColor

        switch state {
        case .loaded:
            bottomFooterButton.isEnabled = true
        case .loading, .failed:
            bottomFooterButton.isEnabled = false
        }

        tableView.layoutIfNeeded()
        checkScrollPosition()
        updateBottomFooterButtonText()
    }

    private func updateBottomFooterButtonText() {
        let title: String
        if isScrolledCloseToBottom {
            title = OWSLocalizedString(
                "BANK_MANDATE_AGREE",
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a label for a button to agree to the mandate."
            )
        } else {
            title = OWSLocalizedString(
                "BANK_MANDATE_READ_MORE",
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a label for a button that shows more of the mandate if it is not all visible."
            )
        }
        bottomFooterButton.setTitle(title, for: .normal)
    }

    private func didTapBottomFooterButton() {
        if isScrolledCloseToBottom {
            self.didAgree(.accept())
        } else {
            let pageHeight = tableView.bounds.height - tableView.safeAreaInsets.top - tableView.safeAreaInsets.bottom
            tableView.contentOffset.y = min(
                tableView.contentOffset.y + pageHeight,
                tableView.contentSize.height
            )
        }
    }

    // MARK: Actions

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }

    private func loadMandate() async {
        let request = OWSRequestFactory.bankMandateRequest(bankTransferType: self.bankTransferType)
        do {
            let response = try await networkManager.makePromise(request: request).awaitable()
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Failed to decode JSON response")
            }
            let mandateText: String = try parser.required(key: "mandate")
            self.state = .loaded(mandateText: mandateText)
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            self.state = .failed
        }
    }

    // MARK: - UIScrollViewDelegate

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        checkScrollPosition()
    }
}

// MARK: - UITextViewDelegate

extension BankTransferMandateViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        present(DonationPaymentDetailsReadMoreSheetViewController(), animated: true)
        return false
    }
}

// MARK: - Stripe Payment Method

extension Stripe.PaymentMethod.Mandate {
    fileprivate static func accept() -> Self {
        .init(mode: .online(
            userAgent: OWSURLSession.userAgentHeaderValueSignalIos,
            ipAddress: "0.0.0.0"
        ))
    }
}
