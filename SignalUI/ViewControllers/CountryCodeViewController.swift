//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public protocol CountryCodeViewControllerDelegate: AnyObject {
    func countryCodeViewController(_ vc: CountryCodeViewController,
                                   didSelectCountry: RegistrationCountryState)
}

// MARK: -

public class CountryCodeViewController: OWSTableViewController2 {
    public weak var countryCodeDelegate: CountryCodeViewControllerDelegate?

    public var interfaceOrientationMask: UIInterfaceOrientationMask = UIDevice.current.defaultSupportedOrientations

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        interfaceOrientationMask
    }

    private let searchBar = OWSSearchBar()

    // MARK: -

    override public func viewDidLoad() {

        // Configure searchBar() before super.viewDidLoad().
        searchBar.delegate = self
        searchBar.placeholder = OWSLocalizedString("SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", comment: "")
        searchBar.sizeToFit()

        let searchBarWrapper = UIStackView()
        searchBarWrapper.axis = .vertical
        searchBarWrapper.alignment = .fill
        searchBarWrapper.addArrangedSubview(searchBar)
        self.topHeader = searchBarWrapper

        super.viewDidLoad()

        self.delegate = self

        self.title = OWSLocalizedString("COUNTRYCODE_SELECT_TITLE", comment: "")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .stop,
            target: self,
            action: #selector(didPressCancel),
            accessibilityIdentifier: "cancel")

        createViews()
    }

    private func createViews() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let countryStates = RegistrationCountryState.buildCountryStates(searchText: searchBar.text)

        let contents = OWSTableContents()
        let section = OWSTableSection()
        for countryState in countryStates {
            let accessibilityIdentifier = "country.\(countryState.countryCode)"
            section.add(OWSTableItem.item(name: countryState.countryName,
                                          accessoryText: countryState.callingCode,
                                          accessibilityIdentifier: accessibilityIdentifier) { [weak self] in
                self?.countryWasSelected(countryState: countryState)
            })
        }
        contents.add(section)

        self.contents = contents
    }

    private func countryWasSelected(countryState: RegistrationCountryState) {
        AssertIsOnMainThread()

        countryCodeDelegate?.countryCodeViewController(self, didSelectCountry: countryState)
        searchBar.resignFirstResponder()
        self.dismiss(animated: true)
    }

    @objc
    private func didPressCancel() {
        self.dismiss(animated: true)
    }
}

// MARK: -

extension CountryCodeViewController: UISearchBarDelegate {

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        AssertIsOnMainThread()

        searchTextDidChange()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        AssertIsOnMainThread()

        searchTextDidChange()
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        AssertIsOnMainThread()

        searchTextDidChange()
    }

    public func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {
        AssertIsOnMainThread()

        searchTextDidChange()
    }

    public func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        AssertIsOnMainThread()

        searchTextDidChange()
    }

    private func searchTextDidChange() {
        updateTableContents()
    }
}

// MARK: -

extension CountryCodeViewController: OWSTableViewControllerDelegate {

    public func tableViewWillBeginDragging(_ tableView: UITableView) {
        searchBar.resignFirstResponder()
    }
}
