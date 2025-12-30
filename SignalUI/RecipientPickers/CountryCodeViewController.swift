//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI
import Combine
import SignalServiceKit

public protocol CountryCodeViewControllerDelegate: AnyObject {
    func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountry: PhoneNumberCountry)
}

private class ViewModel: NSObject, ObservableObject {
    let didSelectCountry = PassthroughSubject<PhoneNumberCountry, Never>()
    @Published var countries: [PhoneNumberCountry] = []

    func buildCountries(searchText: String? = nil) {
        countries = PhoneNumberCountry.buildCountries(searchText: searchText)
    }
}

extension ViewModel: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        buildCountries(searchText: searchBar.text)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        buildCountries()
    }
}

public class CountryCodeViewController: HostingController<CountryCodePicker> {
    private var didSelectCountrySink: AnyCancellable?

    public var interfaceOrientationMask: UIInterfaceOrientationMask = UIDevice.current.defaultSupportedOrientations

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        interfaceOrientationMask
    }

    public init(delegate: CountryCodeViewControllerDelegate) {
        let viewModel = ViewModel()
        super.init(wrappedView: CountryCodePicker(viewModel: viewModel))

        let searchController = UISearchController()
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.delegate = viewModel
        searchController.searchBar.placeholder = OWSLocalizedString(
            "SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT",
            comment: "Placeholder text indicating the user can search for contacts by name or phone number.",
        )
        self.navigationItem.searchController = searchController

        self.title = OWSLocalizedString("COUNTRYCODE_SELECT_TITLE", comment: "")
        self.navigationItem.rightBarButtonItem = .systemItem(.stop) { [weak self] in
            self?.dismiss(animated: true)
        }

        didSelectCountrySink = viewModel.didSelectCountry.sink { [weak delegate, weak self] country in
            guard let self else { return }
            delegate?.countryCodeViewController(self, didSelectCountry: country)
            self.navigationItem.searchController?.isActive = false
            self.dismiss(animated: true)
        }
    }
}

public struct CountryCodePicker: View {
    @ObservedObject fileprivate var viewModel: ViewModel

    public var body: some View {
        SignalList {
            SignalSection {
                ForEach(viewModel.countries) { country in
                    Button {
                        viewModel.didSelectCountry.send(country)
                    } label: {
                        HStack {
                            Text(country.countryName)
                            Spacer()
                            Text(country.plusPrefixedCallingCode)
                                .foregroundStyle(Color.Signal.secondaryLabel)
                        }
                    }
                    .foregroundStyle(Color.Signal.label)
                }
            }
        }
        .onAppear {
            viewModel.buildCountries()
        }
    }
}
