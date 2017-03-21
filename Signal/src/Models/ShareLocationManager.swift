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

/**
 Handle some errors that might occur when trying to share locations
 */
@objc enum ShareLocationManagerStatus: Int {
    case success = 0
    /// The user has not granted permissions to use location services
    case noPermission = 1
    /// The location could not be determined
    case noLocation = 2
    /// Static image could not be retreived
    case noImage = 3
}

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
    
    // MARK: URL components
    
    /// The URL used to include a link in the message
    private let mapsURL = "https://maps.google.com/maps?q=%f,%f"
    
    /// The first part of the URL used to retreive the static image
    private let mapImageURL = "https://maps.googleapis.com/maps/api/staticmap?center="
    
    /// The second part of the URL used to retreive the static image
    private let mapImageURL2 = "&zoom=13&size=400x400&markers=color:red%7C"
    
    /// The url to get the address string
    private let reverseGeoLocationURL = "https://maps.googleapis.com/maps/api/geocode/json?latlng="
    
    // MARK: Reverse Geolocation variables
    
    /// A flag signaling that the request is finished
    private var didFinishReverseLocation = false
    
    /// Save the coordinates and reverse location string when retreived
    private var messageString: String?
    
    // MARK: Static map variables
    
    /// A flag signaling that the image has been retreived
    private var didFinishStaticMapImage = false
    
    /// Save the static image when retreived
    private var staticImage: UIImage?
    
    // MARK: Other variables
    
    /// The location manager to handle requests
    private var locationManager: CLLocationManager!
    
    /// The completion handler that is called when the message is successfully constructed
    private var onCompletion: ShareLocationHandler?
    
    /// Flag indicating that the user has to authorize
    private var waitingForPermissions = false
    
    // MARK: Public Objective-C API
    // TODO: Figure out how to make the requestLocation() function available in Objective-C
    // Then this stuff can be removed
    
    /// Set the completion handler first
    var completionHandler: (() -> ())?
    
    var message: String?
    var image: UIImage?
    
    
    /// Request the location after setting completion handler
    func requestCurrentLocation() {
        requestLocation { mess, img in
            self.message = mess
            self.image = img
            self.completionHandler?()
        }
    }
    
    // MARK: Public Swift API
    
    /**
     Request a message containing the current location. The message consists of three parts:
     - The coordinates in degrees, arcminutes and arcseconds
     - Location information (address, country, ...) if available
     - A maps URL (currently google maps)
     
     Permissions to access the location are handled by requesting permissions to use the
     location when the app is in use. If permission is denied, the completion handler will
     return with an error.
     
     - note: If a request is already in progress, this function will do nothing.
     
     - parameter completionHandler: A closure which is called with either the message or an error
     */
    func requestLocation(completionHandler: @escaping ShareLocationHandler) {
        // Check if request is already in progress
        if locationManager != nil {
            return
        }
        onCompletion = completionHandler
        checkPermissions()
    }
    
    private func finishRequest(withStatus status: ShareLocationManagerStatus) {
        // Only needed for versions <9.0
        locationManager?.stopUpdatingLocation()
        
        switch status {
        case .noImage:
            showNoImageError()
        case .noLocation:
            showNoLocationError()
        case .noPermission:
            showNoPermissionError()
        case .success:
            onCompletion?(messageString!, staticImage!)
        }
        cleanUp()
    }
    
    private func cleanUp() {
        messageString = nil
        staticImage = nil
        locationManager = nil
    }
    
    /**
     Show an error when the image creation failed (probably due to missing internet connection)
    */
    private func showNoImageError() {
        let title = NSLocalizedString("FAILED_GET_STATIC_MAP_TITLE", comment: "No internet connection to get static map image")
        let message = NSLocalizedString("FAILED_GET_STATIC_MAP_BODY", comment: "Signal needs an internet connection to send your current location")
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
        let message = NSLocalizedString("MISSING_LOCATION_PERMISSION_BODY", comment: "Alert body when location is not authorized")
        let okButton = NSLocalizedString("OK", comment:"")
        
        let alert = UIAlertView(title:title, message:message, delegate:nil, cancelButtonTitle:okButton)
        alert.show()
    }
    
    // MARK: received location
    
    /**
     Get address and static image for the location
     
     - parameter coordinates: The coordinates of the location
     */
    private func processLocation(_ coordinates: CLLocationCoordinate2D) {
        self.didFinishReverseLocation = false
        self.didFinishStaticMapImage = false
        self.staticImage = nil
        self.messageString = nil
        
        // Start address request
        getGoogleMapsAddress(location: coordinates) { address in
            let locationString = self.locationDegreesToString(coordinate: coordinates)
            self.messageString = locationString + (address ?? "") + self.getMapURL(for: coordinates)
            self.didFinishReverseLocation = true
            self.checkRequestsFinished()
        }
        
        // Start map image request
        getGoogleMapsImage(for: coordinates) { image in
            self.staticImage = image
            self.didFinishStaticMapImage = true
            self.checkRequestsFinished()
        }
    }
    
    /**
     Check if both reverseGeoLocation and static image request are finished.
     Finish the request if both are done.
     */
    private func checkRequestsFinished() {
        if didFinishStaticMapImage && didFinishReverseLocation {
            if staticImage == nil {
                finishRequest(withStatus: .noImage)
            } else {
                finishRequest(withStatus: .success)
            }
        }
    }
    
    // MARK: Permissions & message construction
    
    /// Check if location access is granted. Either cancel with error or continue
    private func checkPermissions() {
        // Only create manger on first execute, could be called again on permission change
        if locationManager == nil {
            locationManager = CLLocationManager()
        }
        
        switch CLLocationManager.authorizationStatus() {
        case .denied, .restricted:
            finishRequest(withStatus: .noPermission)
            
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
    
    // MARK: Location in arcminutes and arcseconds
    
    /**
     Convert a coordinate to a String representation with arcminutes and arcseconds, as well as N,E,S,W direction specifiers
     
     - parameter coordinate: The location to convert
     
     - returns: The string representation of the coordinate
     */
    private func locationDegreesToString(coordinate: CLLocationCoordinate2D) -> String {
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
        let degs = Int(degrees)
        
        let minutes = Int(60 * (degrees - Double(degs)))
        
        let seconds = 3600 * (degrees - Double(degs))  - 60 * Double(minutes)
        
        let direction = (degs > 0) ? posDir : negDir
        
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
        let url = reverseGeoLocationURL + String(format: "%f,%f", location.latitude, location.longitude)
        getDataFromURL(for: url) { data in
            if data != nil {
                // Could also properly parse JSON file, but this is easier
                if let string = String(data: data!, encoding: .utf8) {
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
    
    // MARK: Google maps
    
    /**
     Create a URL String from a coordinate.
     
     - parameter coordinate: The coordinate to construct the string
     
     - returns: The generated URL as a String
     */
    private func getMapURL(for coordinate: CLLocationCoordinate2D) -> String {
        return String(format: mapsURL, coordinate.latitude, coordinate.longitude)
    }
    
    /**
     Get a static map image from Google maps.
     
     - parameter location: The center position of the image
     - parameter completionHandler: code block to handle the received image (optional UIImage)
     */
    private func getGoogleMapsImage(for location: CLLocationCoordinate2D, completionHandler: @escaping (UIImage?) -> ()) {
        let position = String(format: "%f,%f", location.latitude, location.longitude)
        let url = mapImageURL + position + mapImageURL2 + position
        
        getDataFromURL(for: url) { data in
            if data != nil {
                completionHandler(UIImage(data: data!))
            } else {
                completionHandler(nil)
            }
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
        if let location = locations.last {
            processLocation(location.coordinate)
        } else {
            finishRequest(withStatus: .noLocation)
        }
    }
    
    /// The location update failed, cancel with error
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishRequest(withStatus: .noLocation)
    }
    
    /// Wait for user authorization
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Check if permissions were previously not given
        // For some reason, this method is called when the location is checked with 'locationManager.location'
        if waitingForPermissions {
            checkPermissions()
            waitingForPermissions = false
        }
    }
}

