import UIKit

public var isIPhone5OrSmaller: Bool {
    return (UIScreen.main.bounds.height - 568) < 1
}

public var isIPhone6OrSmaller: Bool {
    return (UIScreen.main.bounds.height - 667) < 1
}
