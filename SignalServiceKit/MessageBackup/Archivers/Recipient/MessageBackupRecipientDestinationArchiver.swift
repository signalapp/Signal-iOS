//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/**
 * Writes and reads ``BackupProtoRecipient`` frames to/from the backup proto.
 *
 * Different types of recipient objects are fanned out to the different concrete implementations of this protocol.
 */
internal protocol MessageBackupRecipientDestinationArchiver: MessageBackupRecipientArchiver {

    /// This method will be called to determine which archiver to use to restore a particular ``BackupProtoRecipient`` frame.
    /// These should be mutually exclusive among all concrete subclasses; typically just presence of a oneOf field.
    static func canRestore(_ recipient: BackupProtoRecipient) -> Bool
}
