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
                        transaction:(DBReadTransaction *)transaction
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

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSString *accountEntropyPool = self.accountEntropyPool;
    if (accountEntropyPool != nil) {
        [coder encodeObject:accountEntropyPool forKey:@"accountEntropyPool"];
    }
    NSData *masterKey = self.masterKey;
    if (masterKey != nil) {
        [coder encodeObject:masterKey forKey:@"masterKey"];
    }
    NSData *mediaRootBackupKey = self.mediaRootBackupKey;
    if (mediaRootBackupKey != nil) {
        [coder encodeObject:mediaRootBackupKey forKey:@"mediaRootBackupKey"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_accountEntropyPool = [coder decodeObjectOfClass:[NSString class] forKey:@"accountEntropyPool"];
    self->_masterKey = [coder decodeObjectOfClass:[NSData class] forKey:@"masterKey"];
    self->_mediaRootBackupKey = [coder decodeObjectOfClass:[NSData class] forKey:@"mediaRootBackupKey"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.accountEntropyPool.hash;
    result ^= self.masterKey.hash;
    result ^= self.mediaRootBackupKey.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSSyncKeysMessage *typedOther = (OWSSyncKeysMessage *)other;
    if (![NSObject isObject:self.accountEntropyPool equalToObject:typedOther.accountEntropyPool]) {
        return NO;
    }
    if (![NSObject isObject:self.masterKey equalToObject:typedOther.masterKey]) {
        return NO;
    }
    if (![NSObject isObject:self.mediaRootBackupKey equalToObject:typedOther.mediaRootBackupKey]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSSyncKeysMessage *result = [super copyWithZone:zone];
    result->_accountEntropyPool = self.accountEntropyPool;
    result->_masterKey = self.masterKey;
    result->_mediaRootBackupKey = self.mediaRootBackupKey;
    return result;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
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
