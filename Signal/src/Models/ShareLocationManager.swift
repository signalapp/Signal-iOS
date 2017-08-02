//
//  ShareLocationManager.swift
//  Signal
//
//  Created by User on 20/03/2017.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

//
//  ShareLocationManager.swift
//  Signal
//
//  Created by User on 20/03/2017.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import CoreLocation

typealias ShareLocationHandler = (String, UIImage) -> ()

/**
 Manages the "share location" function. Request the current location with `requestLocation`, and handle the returned message or error in the completion handler.

 ## Usage example:
 ````
 let shareManager = ShareLocationManager()

 shareManager.requestLocation { message, image in
 // Only called when no error occured
 }
 ````
 */
@objc class ShareLocationManager: NSObject, CLLocationManagerDelegate {
    let TAG = "[ShareLocationManager]"

    // MARK: URL components

    /// The URL used to include a link in the message
    private let mapsURL = "https://maps.google.com/maps?q=%f,%f"

    /// The URL used to retreive the static image, including placeholder for latitude and longitude
    private let mapImageURL = "https://maps.googleapis.com/maps/api/staticmap?center=%f,%f&zoom=13&size=400x400&markers=color:red"

    /// The URL used to get the address string, including placeholder for latitude and longitude
    private let reverseGeoLocationURL = "https://maps.googleapis.com/maps/api/geocode/json?latlng=%f,%f"

    // MARK: Other variables

    /// The location manager to handle requests
    private var locationManager: CLLocationManager!

    /// The completion handler that is called when the message is successfully constructed
    private var onCompletion: ShareLocationHandler?

    /// Flag indicating that the user has to authorize access
    private var waitingForPermissions = false

    // MARK: Public API

    /**
     Request a message containing the current location. The message consists of three parts:
     - The coordinates in degrees, arcminutes and arcseconds
     - Location information (address, country, ...) if available
     - A maps URL (currently google maps)

     Permissions to access the location are handled by requesting permissions to use the
     location when the app is in use.

     - note: If a request is already in progress, this function will do nothing.

     - parameter completionHandler: A closure which is called with the message and image
     */
    func requestLocation(completionHandler:  @escaping (String, UIImage) -> ()) {
        // Check if request is already in progress
        if locationManager != nil {
            Logger.info("\(TAG): Location request already processing")
            return
        }
        onCompletion = completionHandler
        Logger.info("\(TAG): Check for permissions and request location")
        checkPermissions()
    }

    // MARK: Error notifications

    /**
     Show an error when the image creation failed (probably due to missing internet connection)
     */
    private func showNoImageError() {
        let title = NSLocalizedString("FAILED_GET_STATIC_MAP_TITLE", comment: "No internet connection?")
        let message = NSLocalizedString("FAILED_GET_STATIC_MAP_BODY", comment: "Signal could not get information on the current location")
        let okButton = NSLocalizedString("OK", comment:"")

        let alert = UIAlertView(title:title, message:message, delegate:nil, cancelButtonTitle:okButton)
        alert.show()
    }

    /**
     Display an alert when the location can't be determined
     */
    private func showNoLocationError() {
        let title = NSLocalizedString("FAILED_GET_LOCATION_TITLE", comment: "Location unavailable")
        let message = NSLocalizedString("FAILED_GET_LOCATION_BODY", comment: "Signal could not determine your current location.")
        let okButton = NSLocalizedString("OK", comment:"")

        let alert = UIAlertView(title:title, message:message, delegate:nil, cancelButtonTitle:okButton)
        alert.show()
    }

    /**
     Display an Alert when location permissions are denied
     */
    private func showNoPermissionError() {
        let title = NSLocalizedString("MISSING_LOCATION_PERMISSION_TITLE", comment: "Alert title when location is not authorized")
        let body = NSLocalizedString("MISSING_LOCATION_PERMISSION_BODY", comment: "Alert body when location is not authorized")

        let alert = UIAlertController(title: title, message: body, preferredStyle: UIAlertControllerStyle.alert)

        let cancelAction = UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment:""), style: .cancel)
        alert.addAction(cancelAction)
        
        let settingsText = NSLocalizedString("OPEN_SETTINGS_BUTTON", comment:"Button text which opens the settings app")
        let openSettingsAction = UIAlertAction(title: settingsText, style: .default) { (_) in
            UIApplication.shared.openSystemSettings()
        }
        alert.addAction(openSettingsAction)

        UIApplication.shared.frontmostViewController?.present(alert, animated: true, completion: nil)
    }

    // MARK: location processing

    /**
     Get address and static image for the location

     - parameter coordinates: The coordinates of the location
     */
    private func processLocation(_ coordinates: CLLocationCoordinate2D) {
        // Save the static image when retreived
        var image: UIImage?
        var didFinishStaticMapImage = false

        // Save the coordinates and reverse location string when retreived
        var message: String!
        var didFinishReverseLocation = false

        // Start address request
        getGoogleMapsAddress(location: coordinates) { address in
            Logger.debug("\(self.TAG): Retreived address from google maps")
            let locationString = self.getStringFrom(coordinate: coordinates)
            let stringFromCoordinate = String(format: self.mapsURL, coordinates.latitude, coordinates.longitude)
            message = locationString + (address ?? "") + stringFromCoordinate

            if didFinishStaticMapImage {
                self.requestsFinished(with: image, and: message)
            }
            didFinishReverseLocation = true
        }

        // Start map image request
        getGoogleMapsImage(for: coordinates) { theImage in
            if (theImage == nil) {
                Logger.debug("\(self.TAG): Could not retreive image from google maps")
            }
            image = theImage
            if didFinishReverseLocation {
                self.requestsFinished(with: image, and: message)
            }
            didFinishStaticMapImage = true
        }
    }

    /**
     Check if both reverseGeoLocation and static image request are finished.
     Finish the request if both are done.
     */
    private func requestsFinished(with image: UIImage?, and message: String) {
        if image == nil {
            showNoImageError()
            finishRequest()
        } else {
            onCompletion?(message, image!)
            finishRequest()
        }
    }

    private func finishRequest() {
        if #available(iOS 9.0, *) {
            // Nothing to do here, since location was only requested once
        } else {
            locationManager?.stopUpdatingLocation()
        }
        locationManager = nil
        onCompletion = nil
    }

    // MARK: Permissions

    /// Check if location access is granted. Either cancel with error or continue
    private func checkPermissions() {
        // Only create manager on first execute, could be called again on permission change
        if locationManager == nil {
            locationManager = CLLocationManager()
        }

        switch CLLocationManager.authorizationStatus() {
        case .denied, .restricted:
            Logger.info("\(TAG): No permissions to request location");
            showNoPermissionError()
            finishRequest()

        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.delegate = self
            // Check if location is already available
            if let location = locationManager.location {
                processLocation(location.coordinate)
                break
            }
            // Wait for available location
            if #available(iOS 9.0, *) {
                // Only one request is made
                locationManager.requestLocation()
            } else {
                // Need to manually disable updating
                locationManager.startUpdatingLocation()
            }

        case .notDetermined:
            locationManager.delegate = self
            waitingForPermissions = true
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: Location helper functions

    /**
     Convert a coordinate to a String representation with arcminutes and arcseconds, as well as N,E,S,W direction specifiers

     - parameter coordinate: The location to convert

     - returns: The string representation of the coordinate
     */
    private func getStringFrom(coordinate: CLLocationCoordinate2D) -> String {
        let latitude = convertDegreesToString(degrees: coordinate.latitude, posDir: "N", negDir: "S")
        let longitude = convertDegreesToString(degrees: coordinate.longitude, posDir: "E", negDir: "W")
        return latitude + " " + longitude + "\n"
    }

    /**
     Helper function to convert a 1D coordinate to a String

     - note:
     Example conversion: -45.83201° East -> `45° 49' 55.2" W`

     - parameter degrees: The coordinate in degrees. range [-90,90]
     - parameter posDir: String representation of the positive direction (e.g. `N`)
     - parameter negDir: String representation of the negative direction (e.g. `S`)

     - returns: The coordinate represented as a String
     */
    private func convertDegreesToString(degrees: CLLocationDegrees, posDir: String, negDir: String) -> String {
        let direction = (degrees > 0) ? posDir : negDir
        let absDegrees: Double = abs(degrees)
        let degs = Int(absDegrees)
        let minutes = Int(60 * (absDegrees - Double(degs)))
        let seconds = 3600 * (absDegrees - Double(degs))  - 60 * Double(minutes)

        return String(format: "%d°%d'%.1f''", arguments: [abs(degs), minutes, seconds]) + direction
    }

    // MARK: Address information

    /**
     Create a String representation of the placemark

     ## Example
     The coordinates `(37.331686°W,-122.030656° E)` will convert to:

     `1 Infinite Loop, Cupertino, CA 95014, USA`

     - parameter location: The coordinates to use
     - parameter completionHandler: The block to execute with the retrieved string
     - returns: A String description of the location
     */
    private func getGoogleMapsAddress(location: CLLocationCoordinate2D, completionHandler: @escaping (String?) -> ()) {
        let url = String(format: reverseGeoLocationURL, location.latitude, location.longitude)
        getDataFromURL(for: url) { data in
            if let theData = data {
                // Could also properly parse JSON file, but this is easier
                if let string = String(data: theData, encoding: .utf8) {
                    let parts = string.components(separatedBy: "\"formatted_address\" : \"")
                    if parts.count > 1 {
                        completionHandler(parts[1].components(separatedBy: "\",")[0] + "\n")
                        return
                    }
                }
            }
            completionHandler(nil)
        }
    }

    /**
     Get a static map image from Google maps.

     - parameter location: The center position of the image
     - parameter completionHandler: code block to handle the received image (optional UIImage)
     */
    private func getGoogleMapsImage(for location: CLLocationCoordinate2D, completionHandler: @escaping (UIImage?) -> ()) {
        // String is split up because otherwise the % escape messes up the result
        let url = String(format: mapImageURL, location.latitude, location.longitude) + "%7C" + String(format: "%f,%f", location.latitude, location.longitude)

        getDataFromURL(for: url) { data in
            if let theData = data {
                if let theImage = UIImage(data: theData) {
                    completionHandler(theImage)
                    return
                }
            }
            completionHandler(nil)
        }
    }

    /**
     Get data from a url. The completion handler will return the requested data,
     or nil, if the request fails, or the string is not a valid url.

     - note: The fetch is performed on the user initiated queue

     - parameter urlString: The string containing the url
     - parameter completionHandler: Code block which is executed after the request is completed
     */
    private func getDataFromURL(for urlString: String, completionHandler: @escaping (Data?) -> ()) {
        guard let url = URL(string: urlString) else {
            completionHandler(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: url)
            DispatchQueue.main.async {
                completionHandler(data)
            }
        }
    }

    // MARK: CLLocationManagerDelegate

    /// Handle location update. Only called once
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard (manager == locationManager) else {
            return
        }
        if let location = locations.last {
            processLocation(location.coordinate)
        } else {
            showNoLocationError()
            finishRequest()
        }
    }

    /// The location update failed, cancel with error
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (manager == locationManager) else {
            return
        }
        Logger.info("\(TAG): Could not determine location: \(error.localizedDescription)")
        showNoLocationError()
        finishRequest()
    }

    /// Wait for user authorization
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard (manager == locationManager) else {
            return
        }
        // Check if permissions were previously not given
        // For some reason this method is called when the location is checked with 'locationManager.location'
        //if waitingForPermissions {
        //    waitingForPermissions = false
        checkPermissions()
        //}
    }
}

