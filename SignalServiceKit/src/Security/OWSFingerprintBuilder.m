//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

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
    NSData *myIdentityKey = [[OWSIdentityManager shared] identityKeyPair].publicKey;

    return [OWSFingerprint fingerprintWithMyStableAddress:mySignalAddress
                                            myIdentityKey:myIdentityKey
                                       theirStableAddress:theirSignalAddress
                                         theirIdentityKey:theirIdentityKey
                                                theirName:theirName];
}

@end

NS_ASSUME_NONNULL_END
