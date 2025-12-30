//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
        didAgree: @escaping (Stripe.PaymentMethod.Mandate) -> Void,
    ) {
        self.bankTransferType = bankTransferType
        self.didAgree = didAgree
        super.init()
    }

    // MARK: Table setup

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)

        updateTableContents()
        updateBottomFooter()

        Task {
            await loadMandate()
        }
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
    private static let bankIconCircleSize: CGFloat = 64
    /// This URL itself is not used. The action is overridden in the text view delegate function.
    private static let learnMoreURL = URL(string: "https://support.signal.org/")!

    private func makeHeaderView() -> UIView {
        let bankIconView = UIImageView(image: UIImage(systemName: "building.columns"))
        bankIconView.contentMode = .scaleAspectFit
        bankIconView.tintColor = .Signal.label

        let bankIconCircle = CircleView()
        bankIconCircle.backgroundColor = .Signal.secondaryGroupedBackground
        bankIconCircle.addSubview(bankIconView)

        let bankIconContainer = UIView.container()
        bankIconContainer.addSubview(bankIconCircle)

        bankIconView.translatesAutoresizingMaskIntoConstraints = false
        bankIconCircle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bankIconView.widthAnchor.constraint(equalToConstant: Self.bankIconSize),
            bankIconView.heightAnchor.constraint(equalToConstant: Self.bankIconSize),

            bankIconView.centerXAnchor.constraint(equalTo: bankIconCircle.centerXAnchor),
            bankIconView.centerYAnchor.constraint(equalTo: bankIconCircle.centerYAnchor),

            bankIconCircle.widthAnchor.constraint(equalToConstant: Self.bankIconCircleSize),
            bankIconCircle.heightAnchor.constraint(equalToConstant: Self.bankIconCircleSize),

            bankIconCircle.topAnchor.constraint(equalTo: bankIconContainer.topAnchor),
            bankIconCircle.leadingAnchor.constraint(greaterThanOrEqualTo: bankIconContainer.leadingAnchor),
            bankIconCircle.centerXAnchor.constraint(equalTo: bankIconContainer.centerXAnchor),
            bankIconCircle.bottomAnchor.constraint(equalTo: bankIconContainer.bottomAnchor),
        ])

        let titleLabel = UILabel.title1Label(text: OWSLocalizedString(
            "BANK_MANDATE_TITLE",
            comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is the title above that mandate.",
        ))

        let subtitleTextView = LinkingTextView()
        subtitleTextView.delegate = self
        subtitleTextView.attributedText = .composed(of: [
            OWSLocalizedString(
                "BANK_MANDATE_SUBTITLE",
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a subtitle about the payment processor Stripe above that mandate.",
            ),
            " ",
            CommonStrings.learnMore.styled(with: .link(Self.learnMoreURL)),
        ]).styled(with: .color(.Signal.secondaryLabel), .font(.dynamicTypeSubheadline))
        subtitleTextView.textAlignment = .center

        let stackView = UIStackView(arrangedSubviews: [
            bankIconContainer,
            titleLabel,
            subtitleTextView,
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 8
        stackView.setCustomSpacing(12, after: bankIconContainer)

        // Use container to provide some vertical spacing below.
        let container = UIView()
        container.preservesSuperviewLayoutMargins = true
        container.directionalLayoutMargins.bottom = 24
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor),
        ])

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

    private lazy var bottomFooterButton = UIButton(
        configuration: .largePrimary(title: ""),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapBottomFooterButton()
        },
    )

    private lazy var bottomFooterContainer: UIView = {
        let stackView = UIStackView.verticalButtonStack(buttons: [bottomFooterButton])
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    private func updateBottomFooter() {
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
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a label for a button to agree to the mandate.",
            )
        } else {
            title = OWSLocalizedString(
                "BANK_MANDATE_READ_MORE",
                comment: "Users can donate to Signal with a bank account. We are required to show them a mandate with information about bank transfers. This is a label for a button that shows more of the mandate if it is not all visible.",
            )
        }
        bottomFooterButton.configuration?.title = title
    }

    private func didTapBottomFooterButton() {
        if isScrolledCloseToBottom {
            self.didAgree(.accept())
        } else {
            let pageHeight = tableView.bounds.height - tableView.safeAreaInsets.top - tableView.safeAreaInsets.bottom
            let yOffset = min(
                tableView.contentOffset.y + pageHeight,
                tableView.contentSize.height - tableView.bounds.height,
            )
            let newOffset = CGPoint(x: tableView.contentOffset.x, y: yOffset)
            tableView.setContentOffset(newOffset, animated: true)
        }
    }

    // MARK: Actions

    private func loadMandate() async {
        let request = OWSRequestFactory.bankMandateRequest(bankTransferType: self.bankTransferType)
        do {
            let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Missing or invalid JSON")
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
            ipAddress: "0.0.0.0",
        ))
    }
}
