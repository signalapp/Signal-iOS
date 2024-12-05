//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// The possible payment processors for a Backup subscription.
enum BackupPaymentProcessor: String {
    case appleAppStore = "APPLE_APP_STORE"
    case googlePlayBilling = "GOOGLE_PLAY_BILLING"
}
