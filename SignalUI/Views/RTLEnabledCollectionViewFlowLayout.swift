//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public class RTLEnabledCollectionViewFlowLayout: UICollectionViewFlowLayout {

    override public var flipsHorizontallyInOppositeLayoutDirection: Bool { true }
}
