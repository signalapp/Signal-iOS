//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public protocol CountryCodeViewControllerDelegate: AnyObject {
    func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountry: PhoneNumberCountry)
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
        searchBar.placeholder = OWSLocalizedString(
            "SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT",
            comment: "Placeholder text indicating the user can search for contacts by name or phone number."
        )
        searchBar.sizeToFit()

        let searchBarWrapper = UIStackView()
        searchBarWrapper.axis = .vertical
        searchBarWrapper.alignment = .fill
        searchBarWrapper.addArrangedSubview(searchBar)
        self.topHeader = searchBarWrapper

        super.viewDidLoad()

        self.delegate = self

        self.title = OWSLocalizedString("COUNTRYCODE_SELECT_TITLE", comment: "")

        self.navigationItem.leftBarButtonItem = .systemItem(.stop) { [weak self] in
            self?.dismiss(animated: true)
        }

        createViews()
    }

    private func createViews() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let countries = PhoneNumberCountry.buildCountries(searchText: searchBar.text)

        let contents = OWSTableContents()
        let section = OWSTableSection()
        for country in countries {
            section.add(OWSTableItem.item(
                name: country.countryName,
                accessoryText: country.plusPrefixedCallingCode,
                actionBlock: { [weak self] in
                    self?.countryWasSelected(country)
                }
            ))
        }
        contents.add(section)

        self.contents = contents
    }

    private func countryWasSelected(_ country: PhoneNumberCountry) {
        AssertIsOnMainThread()

        countryCodeDelegate?.countryCodeViewController(self, didSelectCountry: country)
        searchBar.resignFirstResponder()
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
