//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SignalServiceAddress;

@protocol ContactsManagerProtocol <NSObject>

/// The name representing this address.
///
/// This will be the first of the following that exists for this address:
/// - System contact name
/// - Profile name
/// - Username
/// - Phone number
/// - "Unknown"
- (NSString *)displayNameStringForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

/// Returns the user's nickname / first name, if supported by the name's locale.
/// If we don't know the user's name components, falls back to displayNameForAddress:
///
/// The user can customize their short name preferences in the system settings app
/// to any of these variants which we respect:
///     * Given Name - Family Initial
///     * Family Name - Given Initial
///     * Given Name Only
///     * Family Name Only
///     * Prefer Nicknames
///     * Full Names Only
- (NSString *)shortDisplayNameStringForAddress:(SignalServiceAddress *)address
                                   transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
