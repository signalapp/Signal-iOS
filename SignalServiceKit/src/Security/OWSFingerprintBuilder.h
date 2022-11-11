//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class OWSFingerprint;
@class TSAccountManager;

@protocol ContactsManagerProtocol;

@class SignalServiceAddress;

@interface OWSFingerprintBuilder : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAccountManager:(TSAccountManager *)accountManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager NS_DESIGNATED_INITIALIZER;

/**
 * Builds a fingerprint combining your current credentials with their most recently accepted credentials.
 */
- (nullable OWSFingerprint *)fingerprintWithTheirSignalAddress:(SignalServiceAddress *)theirSignalAddress;

/**
 * Builds a fingerprint combining your current credentials with the specified identity key.
 * You can use this to present a new identity key for verification.
 */
- (OWSFingerprint *)fingerprintWithTheirSignalAddress:(SignalServiceAddress *)theirSignalAddress
                                     theirIdentityKey:(NSData *)theirIdentityKey;

@end

NS_ASSUME_NONNULL_END
