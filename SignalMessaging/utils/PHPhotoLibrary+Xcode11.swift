//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PhotosUI

// TODO Xcode 12: Delete this file once we're compling only in Xcode 12

#if swift(<5.3)
@objc
public enum PHAccessLevel: Int {
    case addOnly = 1
    case readWrite = 2
}

public extension PHAuthorizationStatus {
    static let limited = PHAuthorizationStatus(rawValue: 4) ?? .authorized
}
#endif

@objc
public extension PHPhotoLibrary {
    @available(iOS 14, *)
    class func ows_presentLimitedLibraryPicker(from viewController: UIViewController) {
        #if swift(>=5.3)
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
        #else
        CurrentAppContext().openSystemSettings()
        #endif
    }

    @available(iOS 14, *)
    class func ows_authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        typealias Type = @convention(c) (AnyObject, Selector, PHAccessLevel) -> PHAuthorizationStatus
        let selector = NSSelectorFromString("authorizationStatusForAccessLevel:")
        let implementation = class_getMethodImplementation(objc_getMetaClass("PHPhotoLibrary") as? AnyClass, selector)
        let authorizationStatus = unsafeBitCast(implementation, to: Type.self)
        return authorizationStatus(self, selector, accessLevel)
    }
}
