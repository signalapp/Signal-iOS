//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol ImageEditorTransformable: ImageEditorItem {
    var unitCenter: ImageEditorSample { get }
    var scaling: CGFloat { get }
    var rotationRadians: CGFloat { get }
    func copy(unitCenter: CGPoint) -> Self
    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> Self
}
