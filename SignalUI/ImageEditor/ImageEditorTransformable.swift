//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol ImageEditorTransformable: ImageEditorItem {
    var unitCenter: ImageEditorSample { get }
    var scaling: CGFloat { get }
    var rotationRadians: CGFloat { get }
    func with(unitCenter: CGPoint) -> Self
    func with(scaling: CGFloat, rotationRadians: CGFloat) -> Self
}
