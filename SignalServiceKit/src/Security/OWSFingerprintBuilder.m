//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSFingerprintBuilder.h"
#import "ContactsManagerProtocol.h"
#import "OWSFingerprint.h"
#import "OWSIdentityManager.h"
#import "TSAccountManager.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSFingerprintBuilder ()

@property (nonatomic, readonly) TSAccountManager *accountManager;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;

@end

@implementation OWSFingerprintBuilder

- (instancetype)initWithAccountManager:(TSAccountManager *)accountManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _accountManager = accountManager;
    _contactsManager = contactsManager;

    return self;
}

- (nullable OWSFingerprint *)fingerprintWithTheirSignalAddress:(SignalServiceAddress *)theirSignalAddress
{
    NSData *_Nullable theirIdentityKey = [[OWSIdentityManager shared] identityKeyForAddress:theirSignalAddress];

    if (theirIdentityKey == nil) {
        OWSFailDebug(@"Missing their identity key");
        return nil;
    }

    return [self fingerprintWithTheirSignalAddress:theirSignalAddress theirIdentityKey:theirIdentityKey];
}

- (OWSFingerprint *)fingerprintWithTheirSignalAddress:(SignalServiceAddress *)theirSignalAddress
                                     theirIdentityKey:(NSData *)theirIdentityKey
{
    NSString *theirName = [self.contactsManager displayNameForAddress:theirSignalAddress];

    SignalServiceAddress *mySignalAddress = [self.accountManager localAddress];
    // PNI TODO: This should use the identity key associated with our PNI if we only have a PNI session with them.
    NSData *myIdentityKey = [[OWSIdentityManager shared] identityKeyPairForIdentity:OWSIdentityACI].publicKey;

    return [OWSFingerprint fingerprintWithMyStableAddress:mySignalAddress
                                            myIdentityKey:myIdentityKey
                                       theirStableAddress:theirSignalAddress
                                         theirIdentityKey:theirIdentityKey
                                                theirName:theirName];
}

@end

NS_ASSUME_NONNULL_END
