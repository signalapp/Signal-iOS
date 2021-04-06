//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class PaymentsCurrencyViewController: OWSTableViewController2 {

    private let searchBar = OWSSearchBar()

    fileprivate var searchText: String? {
        searchBar.text?.ows_stripped()
    }

    public override required init() {
        super.init()

        topHeader = OWSTableViewController2.buildTopHeader(forView: searchBar)
    }

    @objc
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_SET_CURRENCY",
                                  comment: "Title for the 'set currency' view in the app settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))

        searchBar.placeholder = CommonStrings.searchBarPlaceholder
        searchBar.delegate = self

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(paymentConversionRatesDidChange),
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
            object: nil
        )
    }

    public override func applyTheme() {
        super.applyTheme()

        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        paymentsCurrencies.updateConversationRatesIfStale()
    }

    private func updateTableContents() {
        if let searchText = searchText,
           !searchText.isEmpty {
            updateTableContentsForSearch(searchText: searchText)
        } else {
            updateTableContentsDefault()
        }
    }

    private func updateTableContentsDefault() {
        let contents = OWSTableContents()

        let currentCurrencyCode = paymentsCurrencies.currentCurrencyCode
        let preferredCurrencyInfos = paymentsCurrenciesSwift.preferredCurrencyInfos
        let supportedCurrencyInfos = paymentsCurrenciesSwift.supportedCurrencyInfosWithCurrencyConversions

        let preferredSection = OWSTableSection()
        preferredSection.customHeaderHeight = 12
        preferredSection.separatorInsetLeading = NSNumber(value: Double(OWSTableViewController2.cellHInnerMargin))
        for currencyInfo in preferredCurrencyInfos {
            preferredSection.add(buildTableItem(forCurrencyInfo: currencyInfo,
                                                currentCurrencyCode: currentCurrencyCode))
        }
        contents.addSection(preferredSection)

        let supportedSection = OWSTableSection()
        supportedSection.separatorInsetLeading = NSNumber(value: Double(OWSTableViewController2.cellHInnerMargin))
        supportedSection.headerTitle = NSLocalizedString("SETTINGS_PAYMENTS_CURRENCY_VIEW_SECTION_ALL_CURRENCIES",
                                                         comment: "Label for 'all currencies' section in the payment currency settings.")
        if supportedCurrencyInfos.isEmpty {
            supportedSection.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()

                let activityIndicator = UIActivityIndicatorView(style: Theme.isDarkThemeEnabled
                                                                    ? .white
                                                                    : .gray)
                activityIndicator.startAnimating()

                cell.contentView.addSubview(activityIndicator)
                activityIndicator.autoHCenterInSuperview()
                activityIndicator.autoPinEdge(toSuperviewMargin: .top, withInset: 16)
                activityIndicator.autoPinEdge(toSuperviewMargin: .bottom, withInset: 16)

                return cell
            },
            actionBlock: nil))
        } else {
            for currencyInfo in supportedCurrencyInfos {
                supportedSection.add(buildTableItem(forCurrencyInfo: currencyInfo,
                                                    currentCurrencyCode: currentCurrencyCode))
            }
        }
        contents.addSection(supportedSection)

        self.contents = contents
    }

    private func updateTableContentsForSearch(searchText: String) {

        let searchText = searchText.lowercased()

        let contents = OWSTableContents()

        let currentCurrencyCode = paymentsCurrencies.currentCurrencyCode
        let preferredCurrencyInfos = paymentsCurrenciesSwift.preferredCurrencyInfos
        let supportedCurrencyInfos = paymentsCurrenciesSwift.supportedCurrencyInfosWithCurrencyConversions

        let currencyInfosToSearch = supportedCurrencyInfos.isEmpty ? preferredCurrencyInfos : supportedCurrencyInfos
        let matchingCurrencyInfos = currencyInfosToSearch.filter { currencyInfo in
            // We do the simplest possible matching.
            // No terms, no sorting by match quality, etc.
            (currencyInfo.name.lowercased().contains(searchText) ||
                currencyInfo.currencyCode.lowercased().contains(searchText))
        }

        let resultsSection = OWSTableSection()
        resultsSection.customHeaderHeight = 12
        if matchingCurrencyInfos.isEmpty {
            for currencyInfo in matchingCurrencyInfos {
                resultsSection.add(buildTableItem(forCurrencyInfo: currencyInfo,
                                                  currentCurrencyCode: currentCurrencyCode))
            }
        } else {
            for currencyInfo in matchingCurrencyInfos {
                resultsSection.add(buildTableItem(forCurrencyInfo: currencyInfo,
                                                  currentCurrencyCode: currentCurrencyCode))
            }
        }
        contents.addSection(resultsSection)

        self.contents = contents
    }

    private func buildTableItem(forCurrencyInfo currencyInfo: CurrencyInfo,
                                currentCurrencyCode: PaymentsCurrencies.CurrencyCode) -> OWSTableItem {

        let currencyCode = currencyInfo.currencyCode

        return OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let nameLabel = UILabel()
            nameLabel.text = currencyInfo.name
            nameLabel.font = UIFont.ows_dynamicTypeBodyClamped
            nameLabel.textColor = Theme.primaryTextColor

            let currencyCodeLabel = UILabel()
            currencyCodeLabel.text = currencyCode.uppercased()
            currencyCodeLabel.font = UIFont.ows_dynamicTypeFootnoteClamped
            currencyCodeLabel.textColor = Theme.secondaryTextAndIconColor

            let stackView = UIStackView(arrangedSubviews: [ nameLabel, currencyCodeLabel ])
            stackView.axis = .vertical
            stackView.alignment = .fill
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            cell.accessibilityIdentifier = "currency.\(currencyCode)"
            cell.accessibilityLabel = currencyInfo.name
            cell.isAccessibilityElement = true

            if currencyCode == currentCurrencyCode {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }

            return cell
        },
        actionBlock: { [weak self] in
            self?.didSelectCurrency(currencyCode)
        })
    }

    // MARK: - Events

    @objc
    func didTapCancel() {
        navigationController?.popViewController(animated: true)
    }

    private func didSelectCurrency(_ currencyCode: PaymentsCurrencies.CurrencyCode) {
        Self.databaseStorage.write { transaction in
            Self.paymentsCurrencies.setCurrentCurrencyCode(currencyCode, transaction: transaction)
        }
        navigationController?.popViewController(animated: true)
    }

    @objc
    func paymentConversionRatesDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}

// MARK: -

extension PaymentsCurrencyViewController: UISearchBarDelegate {
    open func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateTableContents()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        updateTableContents()
    }
}
