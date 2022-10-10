// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum DismissType {
    /// If this screen is within a navigation controller and isn't the first screen, it will trigger a `popViewController` otherwise
    /// this will trigger a `dismiss`
    case auto
    
    /// This will only trigger a `popViewController` call (if the screen was presented it'll do nothing)
    case pop
    
    /// This will only trigger a `dismiss` call (if the screen was pushed to a presented navigation controller it'll dismiss
    /// the navigation controller, otherwise this will do nothing)
    case dismiss
}
