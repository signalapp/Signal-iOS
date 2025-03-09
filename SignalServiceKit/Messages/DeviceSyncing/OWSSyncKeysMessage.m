//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncKeysMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncKeysMessage ()

@property (nonatomic, readonly, nullable) NSString *accountEntropyPool;
@property (nonatomic, readonly, nullable) NSData *masterKey;
@property (nonatomic, readonly, nullable) NSData *mediaRootBackupKey;

@end

@implementation OWSSyncKeysMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                 accountEntropyPool:(nullable NSString *)accountEntropyPool
                          masterKey:(nullable NSData *)masterKey
                 mediaRootBackupKey:(nullable NSData *)mediaRootBackupKey
                        transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return nil;
    }

    _accountEntropyPool = accountEntropyPool;
    _masterKey = masterKey;
    _mediaRootBackupKey = mediaRootBackupKey;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageKeysBuilder *keysBuilder = [SSKProtoSyncMessageKeys builder];

    if (self.accountEntropyPool) {
        keysBuilder.accountEntropyPool = self.accountEntropyPool;
    }
    if (self.masterKey) {
        keysBuilder.master = self.masterKey;
    }
    if (self.mediaRootBackupKey) {
        keysBuilder.mediaRootBackupKey = self.mediaRootBackupKey;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.keys = [keysBuilder buildInfallibly];
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
