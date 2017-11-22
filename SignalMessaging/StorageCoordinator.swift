//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StorageCoordinator: NSObject {

    @objc
    public static let shared = StorageCoordinator()

    @objc
    public let path = "foo"
}
