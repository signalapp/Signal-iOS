//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    /**
     * When creating and restoring from a message backup, we need to map to/from
     * the backup-scoped identifers to their equivalents in our codebase.
     * For example, we need to map a TSThread.uniqueId to and from the BackupProto's
     * Chat.id.
     *
     * This class is an abstraction over a dictionary that does two things:
     * 1. Allows us to swap out an in-memory implementation for an on-disk implementation,
     * if in practice there are too many identifiers to keep in memory.
     * 2. Ensures we use pass-by-reference instead of pass-by-value that could result
     * in copies (using more memory) and requiring the `inout` keyword.
     *
     * MOST of the time, you should not worry about copying when passing by value;
     * the compiler is smart and only actually copies on write. In this case, though, we
     * really do want a single in-memory (or on-disk) map shared throughout a single
     * backup pass, and we want to modify it as we go.
     */
    internal class SharedMap<K: Hashable, V> {

        private var map = [K: V]()

        subscript(_ key: K) -> V? {
            get { map[key] }
            set(value) { map[key] = value }
        }
    }
}
