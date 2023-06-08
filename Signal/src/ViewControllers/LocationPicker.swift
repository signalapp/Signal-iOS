//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//  Originally based on https://github.com/almassapargali/LocationPicker
//
//  Created by Almas Sapargali on 7/29/15.
//  Parts Copyright (c) 2015 almassapargali. All rights reserved.

import Contacts
import CoreLocation
import CoreServices
import MapKit
import SignalMessaging
import SignalUI

public protocol LocationPickerDelegate: AnyObject {
    func didPickLocation(_ locationPicker: LocationPicker, location: Location)
}

public class LocationPicker: UIViewController {

    public weak var delegate: LocationPickerDelegate?
    public var location: Location? { didSet { updateAnnotation() } }

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var localSearch: MKLocalSearch?

    private lazy var mapView = MKMapView()

    private lazy var resultsController: LocationSearchResults = {
        let locationResults = LocationSearchResults()
        locationResults.onSelectLocation = { [weak self] in self?.selectedLocation($0) }
        return locationResults
    }()

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController(searchResultsController: resultsController)
        searchController.searchResultsUpdater = self
        searchController.hidesNavigationBarDuringPresentation = false
        return searchController
    }()

    private lazy var searchBar: UISearchBar = {
        let searchBar = self.searchController.searchBar
        searchBar.placeholder = OWSLocalizedString("LOCATION_PICKER_SEARCH_PLACEHOLDER",
                                                  comment: "A string indicating that the user can search for a location")
        return searchBar
    }()

    private let supportsTranslucentBars: Bool = {
        // On iOS 13.1 and later, translucent search bars
        // within the nav item's searchController work correctly.
        // Prior to that, they have a weird behavior when the
        // search bar becomes first responder that we want to avoid.
        guard #available(iOS 13.1, *) else { return false }

        return true
    }()

    private static let SearchTermKey = "SearchTermKey"
    private var searchTimer: Timer?

    deinit {
        searchTimer?.invalidate()
        localSearch?.cancel()
        geocoder.cancelGeocode()
    }

    open override func loadView() {
        view = mapView

        let currentLocationButton = UIButton()
        currentLocationButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        currentLocationButton.clipsToBounds = true
        currentLocationButton.layer.cornerRadius = 24

        // This icon doesn't look right when it's actually centered due to its odd shape.
        currentLocationButton.setTemplateImageName("current-location-outline-24", tintColor: .white)
        currentLocationButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 2)

        view.addSubview(currentLocationButton)
        currentLocationButton.autoSetDimensions(to: CGSize(square: 48))
        currentLocationButton.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 15)
        currentLocationButton.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 15)

        currentLocationButton.addTarget(self, action: #selector(didPressCurrentLocation), for: .touchUpInside)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("LOCATION_PICKER_TITLE", comment: "The title for the location picker view")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "x-24")?.withRenderingMode(.alwaysTemplate),
            style: .plain,
            target: self,
            action: #selector(cancelButtonPressed)
        )

        locationManager.delegate = self
        mapView.delegate = self

        OWSSearchBar.applyTheme(to: searchBar)

        searchBar.isTranslucent = supportsTranslucentBars

        // When the search bar isn't translucent, it doesn't allow
        // setting the textField's backgroundColor. Instead, we need
        // to use the background image.
        let backgroundImage = UIImage(
            color: Theme.searchFieldBackgroundColor,
            size: CGSize(square: 36)
        ).withCornerRadius(10)
        searchBar.setSearchFieldBackgroundImage(backgroundImage, for: .normal)
        searchBar.searchTextPositionAdjustment = UIOffset(horizontal: 8.0, vertical: 0.0)
        searchBar.textField?.backgroundColor = .clear

        navigationItem.searchController = searchController
        definesPresentationContext = true

        // Select a new location by long pressing
        let locationSelectGesture = UILongPressGestureRecognizer(target: self, action: #selector(addLocation))
        mapView.addGestureRecognizer(locationSelectGesture)

        // If we don't have location access granted, this does nothing.
        // If we do, this will start the map at the user's current location.
        mapView.showsUserLocation = true
        showCurrentLocation(requestAuthorizationIfNecessary: false)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isTranslucent = supportsTranslucentBars
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        navigationController?.navigationBar.isTranslucent = true
    }

    @objc
    private func cancelButtonPressed(_ sender: UIButton) {
        if let navigation = navigationController, navigation.viewControllers.count > 1 {
            navigation.popViewController(animated: true)
        } else {
            presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }

    @objc
    private func didPressCurrentLocation() {
        showCurrentLocation()
    }

    func showCurrentLocation(requestAuthorizationIfNecessary: Bool = true) {
        if requestAuthorizationIfNecessary { requestAuthorization() }
        locationManager.startUpdatingLocation()
    }

    func requestAuthorization() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedWhenInUse, .authorizedAlways:
            // We are already authorized, do nothing!
            break
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // The user previous explicitly denied access. Point them to settings to re-enable.
            let alert = ActionSheetController(
                title: OWSLocalizedString("MISSING_LOCATION_PERMISSION_TITLE",
                                         comment: "Alert title indicating the user has denied location permissions"),
                message: OWSLocalizedString("MISSING_LOCATION_PERMISSION_MESSAGE",
                                           comment: "Alert body indicating the user has denied location permissions")
            )
            let openSettingsAction = ActionSheetAction(
                title: CommonStrings.openSettingsButton,
                style: .default
            ) { _ in UIApplication.shared.openSystemSettings()  }
            alert.addAction(openSettingsAction)

            let dismissAction = ActionSheetAction(title: CommonStrings.dismissButton, style: .cancel, handler: nil)
            alert.addAction(dismissAction)
            presentActionSheet(alert)
        @unknown default:
            owsFailDebug("Unknown")
        }
    }

    func updateAnnotation() {
        mapView.removeAnnotations(mapView.annotations)
        if let location = location {
            mapView.addAnnotation(location)
            mapView.selectAnnotation(location, animated: true)
        }
    }

    func showCoordinates(_ coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        // The amount of meters +/- the selected coordinate we want to ensure are visible on screen.
        let metersOffset: CLLocationDistance = 600
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: metersOffset, longitudinalMeters: metersOffset)
        mapView.setRegion(region, animated: animated)
    }

    func selectLocation(location: CLLocation) {
        // add point annotation to map
        let annotation = MKPointAnnotation()
        annotation.coordinate = location.coordinate
        mapView.addAnnotation(annotation)

        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { response, error in
            let error = error as NSError?
            let geocodeCanceled = error?.domain == kCLErrorDomain && error?.code == CLError.Code.geocodeCanceled.rawValue

            if let error = error, !geocodeCanceled {
                // show error and remove annotation
                let alert = ActionSheetController(title: nil, message: error.userErrorDescription)
                alert.addAction(ActionSheetAction(title: CommonStrings.okayButton,
                                              style: .cancel, handler: { _ in }))
                self.present(alert, animated: true) {
                    self.mapView.removeAnnotation(annotation)
                }
            } else if let placemark = response?.first {
                // get POI name from placemark if any
                let name = placemark.areasOfInterest?.first

                // pass user selected location too
                self.location = Location(name: name, location: location, placemark: placemark)
            }
        }
    }
}

extension LocationPicker: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // The user requested we select their current location, do so and then stop listening for location updates.
        guard let location = locations.first else {
            return owsFailDebug("Unexpectedly received location update with no location")
        }
        // Only animate if this is not the first location we're showing.
        let shouldAnimate = self.location != nil
        showCoordinates(location.coordinate, animated: shouldAnimate)
        selectLocation(location: location)
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // If location permission was just granted, show the current location
        guard status == .authorizedWhenInUse else { return }
        showCurrentLocation()
    }
}

// MARK: Searching

extension LocationPicker: UISearchResultsUpdating {
    public func updateSearchResults(for searchController: UISearchController) {
        guard let term = searchController.searchBar.text else { return }

        // clear old results
        showItemsForSearchResult(nil)

        searchTimer?.invalidate()
        searchTimer = nil

        let searchTerm = term.trimmingCharacters(in: CharacterSet.whitespaces)
        if !searchTerm.isEmpty {
            // Search after a slight delay to debounce while the user is typing.
            searchTimer = Timer.weakScheduledTimer(
                withTimeInterval: 0.1,
                target: self,
                selector: #selector(searchFromTimer),
                userInfo: [LocationPicker.SearchTermKey: searchTerm],
                repeats: false
            )
        }
    }

    @objc
    private func searchFromTimer(_ timer: Timer) {
        guard let userInfo = timer.userInfo as? [String: AnyObject],
            let term = userInfo[LocationPicker.SearchTermKey] as? String else {
                return owsFailDebug("Unexpectedly attempted to search with no term")
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term

        if let location = locationManager.location {
            // If we have a currently selected location, search relative to that location,
            // where the +/- degrees of the region we're searching around is reflected
            // by the latitude and longitude delta below.
            let latlongDelta: CLLocationDegrees = 2

            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: latlongDelta, longitudeDelta: latlongDelta)
            )
        }

        localSearch?.cancel()
        localSearch = MKLocalSearch(request: request)
        localSearch?.start { [weak self] response, _ in
            self?.showItemsForSearchResult(response)
        }
    }

    func showItemsForSearchResult(_ searchResult: MKLocalSearch.Response?) {
        resultsController.locations = searchResult?.mapItems.map { Location(name: $0.name, placemark: $0.placemark) } ?? []
        resultsController.tableView.reloadData()
    }

    func selectedLocation(_ location: Location) {
        // dismiss search results
        dismiss(animated: true) {
            // set location, this also adds annotation
            self.location = location
            self.showCoordinates(location.coordinate)
        }
    }
}

// MARK: Selecting location with gesture

extension LocationPicker {
    @objc
    private func addLocation(_ gestureRecognizer: UIGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let point = gestureRecognizer.location(in: mapView)
            let coordinates = mapView.convert(point, toCoordinateFrom: mapView)
            let location = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
            selectLocation(location: location)
        }
    }
}

// MARK: MKMapViewDelegate

extension LocationPicker: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        let pin = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "annotation")
        pin.pinTintColor = Theme.accentBlueColor
        pin.animatesDrop = annotation is MKPointAnnotation
        pin.rightCalloutAccessoryView = sendLocationButton()
        pin.canShowCallout = true
        return pin
    }

    func sendLocationButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(imageLiteralResourceName: "send-blue-30"), for: .normal)
        button.sizeToFit()
        return button
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if let location = location {
            delegate?.didPickLocation(self, location: location)
        }

        if let navigation = navigationController, navigation.viewControllers.count > 1 {
            navigation.popViewController(animated: true)
        } else {
            presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }

    public func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        if let userPin = views.first(where: { $0.annotation is MKUserLocation }) {
            userPin.canShowCallout = false
        }
    }
}

// MARK: UISearchBarDelegate

class LocationSearchResults: UITableViewController {
    var locations: [Location] = []
    var onSelectLocation: ((Location) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        extendedLayoutIncludesOpaqueBars = true
        tableView.backgroundColor = Theme.backgroundColor
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return locations.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LocationCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "LocationCell")

        let location = locations[indexPath.row]
        cell.textLabel?.text = location.name
        cell.textLabel?.textColor = Theme.primaryTextColor
        cell.detailTextLabel?.text = location.singleLineAddress
        cell.detailTextLabel?.textColor = Theme.secondaryTextAndIconColor
        cell.backgroundColor = Theme.backgroundColor

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelectLocation?(locations[indexPath.row])
    }
}

public class Location: NSObject {
    public let name: String?

    // difference from placemark location is that if location was reverse geocoded,
    // then location point to user selected location
    public let location: CLLocation
    public let placemark: CLPlacemark

    static let postalAddressFormatter = CNPostalAddressFormatter()

    public var address: String? {
        guard let postalAddress = placemark.postalAddress else {
            return nil
        }
        return Location.postalAddressFormatter.string(from: postalAddress)
    }

    public var singleLineAddress: String? {
        guard let formattedAddress = address else {
            return nil
        }
        let addressLines = formattedAddress.components(separatedBy: .newlines)
        return ListFormatter.localizedString(byJoining: addressLines)
    }

    public var urlString: String {
        return "https://maps.google.com/maps?q=\(coordinate.latitude)%2C\(coordinate.longitude)"
    }

    enum LocationError: Error {
        case assertion
    }

    public func generateSnapshot() -> Promise<UIImage> {
        return Promise { future in
            let options = MKMapSnapshotter.Options()

            // this is the plus/minus meter range from the given coordinate
            // that we'd like to capture in our map snapshot.
            let metersOffset: CLLocationDistance = 300

            options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: metersOffset, longitudinalMeters: metersOffset)

            // The output size will be 256 * the device's scale. We don't adjust the
            // scale directly on the options to ensure a consistent size because it
            // produces poor results on some devices.
            options.size = CGSize(square: 256)

            MKMapSnapshotter(options: options).start(with: .global()) { snapshot, error in
                guard error == nil else {
                    owsFailDebug("Unexpectedly failed to capture map snapshot \(error!)")
                    return future.reject(LocationError.assertion)
                }

                guard let snapshot = snapshot else {
                    owsFailDebug("snapshot unexpectedly nil")
                    return future.reject(LocationError.assertion)
                }

                // Draw our location pin on the snapshot

                UIGraphicsBeginImageContextWithOptions(options.size, true, 0)
                snapshot.image.draw(at: .zero)

                let pinView = MKPinAnnotationView(annotation: nil, reuseIdentifier: nil)
                pinView.pinTintColor = Theme.accentBlueColor
                let pinImage = pinView.image

                var point = snapshot.point(for: self.coordinate)

                let pinCenterOffset = pinView.centerOffset
                point.x -= pinView.bounds.size.width / 2
                point.y -= pinView.bounds.size.height / 2
                point.x += pinCenterOffset.x
                point.y += pinCenterOffset.y
                pinImage?.draw(at: point)

                let image = UIGraphicsGetImageFromCurrentImageContext()

                UIGraphicsEndImageContext()

                guard let finalImage = image else {
                    owsFailDebug("image unexpectedly nil")
                    return future.reject(LocationError.assertion)
                }

                future.resolve(finalImage)
            }
        }
    }

    public init(name: String?, location: CLLocation? = nil, placemark: CLPlacemark) {
        self.name = name
        self.location = location ?? placemark.location!
        self.placemark = placemark
    }

    public func prepareAttachment() -> Promise<SignalAttachment> {
        return generateSnapshot().map(on: DispatchQueue.global()) { image in
            guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
                throw LocationError.assertion
            }

            let dataSource = DataSourceValue.dataSource(with: jpegData, utiType: kUTTypeJPEG as String)
            return SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeJPEG as String)
        }
    }

    public var messageText: String {
        // The message body will look something like:
        //
        // Place Name, 123 Street Name
        //
        // https://maps.google.com/maps

        if let address = address {
            return address + "\n\n" + urlString
        } else {
            return urlString
        }
    }
}

extension Location: MKAnnotation {

    public var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }

    public var title: String? {
        if let name = name {
            return name
        } else if let postalAddress = placemark.postalAddress,
                  let firstAddressLine = Location.postalAddressFormatter.string(from: postalAddress).components(separatedBy: .newlines).first {
            return firstAddressLine
        } else {
            return "\(coordinate.latitude), \(coordinate.longitude)"
        }
    }
}
