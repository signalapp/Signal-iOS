//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncKeysMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncKeysMessage ()

@property (nonatomic, readonly, nullable) NSData *storageServiceKey;
@property (nonatomic, readonly, nullable) NSData *masterKey;

@end

@implementation OWSSyncKeysMessage

- (instancetype)initWithThread:(TSThread *)thread
             storageServiceKey:(nullable NSData *)storageServiceKey
                     masterKey:(nullable NSData *)masterKey
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return nil;
    }

    _storageServiceKey = storageServiceKey;
    _masterKey = masterKey;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageKeysBuilder *keysBuilder = [SSKProtoSyncMessageKeys builder];
    
    if (self.storageServiceKey) {
        keysBuilder.storageService = self.storageServiceKey;
    }
    if (self.masterKey) {
        keysBuilder.master = self.masterKey;
    }

    NSError *error;
    SSKProtoSyncMessageKeys *_Nullable keysProto = [keysBuilder buildAndReturnError:&error];
    if (error || !keysProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.keys = keysProto;
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
