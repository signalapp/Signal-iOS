//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

final public class RTLEnabledCollectionViewFlowLayout: UICollectionViewFlowLayout {

    public override var flipsHorizontallyInOppositeLayoutDirection: Bool { true }
}
