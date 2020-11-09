//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAccountManager;
@class OWSFingerprint;
@protocol ContactsManagerProtocol;

@interface OWSFingerprintBuilder : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAccountManager:(TSAccountManager *)accountManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager NS_DESIGNATED_INITIALIZER;

/**
 * Builds a fingerprint combining your current credentials with their most recently accepted credentials.
 */
- (nullable OWSFingerprint *)fingerprintWithTheirSignalId:(NSString *)theirSignalId;

/**
 * Builds a fingerprint combining your current credentials with the specified identity key.
 * You can use this to present a new identity key for verification.
 */
- (OWSFingerprint *)fingerprintWithTheirSignalId:(NSString *)theirSignalId theirIdentityKey:(NSData *)theirIdentityKey;

@end

NS_ASSUME_NONNULL_END
