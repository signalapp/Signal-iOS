//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * This class doesn't actually do anything (yet?).
 * It's just an example class to prove the embedded framework is correctly
 * integrated with Signal-iOS and the Sharing Extension.
 */
@objc
public class StorageCoordinator: NSObject {

    @objc
    public static let shared = StorageCoordinator()

    @objc
    public let path = "foo"
}
