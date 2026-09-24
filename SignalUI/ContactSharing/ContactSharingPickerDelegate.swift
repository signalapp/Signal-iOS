//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@MainActor
public protocol ContactSharingPickerDelegate: AnyObject {
    func contactSharingPickerDidCancel(_ picker: ContactSharingPickerViewController)
}
