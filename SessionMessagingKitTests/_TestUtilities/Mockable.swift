// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

protocol Mockable {
    associatedtype Key: Hashable
    
    var mockData: [Key: Any] { get }
}
