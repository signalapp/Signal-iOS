//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncKeysMessage.h"
#import <SignalServiceKit/OWSProvisioningMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncKeysMessage ()

@property (nonatomic, readonly, nullable) NSData *storageServiceKey;

@end

@implementation OWSSyncKeysMessage

- (instancetype)initWithThread:(TSThread *)thread storageServiceKey:(nullable NSData *)storageServiceKey
{
    self = [super initWithThread:thread];
    if (!self) {
        return nil;
    }

    _storageServiceKey = storageServiceKey;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction;
{
    SSKProtoSyncMessageKeysBuilder *keysBuilder = [SSKProtoSyncMessageKeys builder];
    
    if (self.storageServiceKey) {
        keysBuilder.storageService = self.storageServiceKey;
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

@end

NS_ASSUME_NONNULL_END
