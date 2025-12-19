//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSStickerPackSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStickerPackSyncMessage ()

@property (nonatomic, readonly) NSArray<StickerPackInfo *> *packs;
@property (nonatomic, readonly) StickerPackOperationType operationType;

@end

#pragma mark -

@implementation OWSStickerPackSyncMessage

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:[self valueForKey:@"operationType"] forKey:@"operationType"];
    NSArray *packs = self.packs;
    if (packs != nil) {
        [coder encodeObject:packs forKey:@"packs"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_operationType = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                            forKey:@"operationType"] unsignedIntegerValue];
    self->_packs = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [StickerPackInfo class] ]]
                                         forKey:@"packs"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.operationType;
    result ^= self.packs.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSStickerPackSyncMessage *typedOther = (OWSStickerPackSyncMessage *)other;
    if (self.operationType != typedOther.operationType) {
        return NO;
    }
    if (![NSObject isObject:self.packs equalToObject:typedOther.packs]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSStickerPackSyncMessage *result = [super copyWithZone:zone];
    result->_operationType = self.operationType;
    result->_packs = self.packs;
    return result;
}

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                              packs:(NSArray<StickerPackInfo *> *)packs
                      operationType:(StickerPackOperationType)operationType
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return self;
    }

    _packs = packs;
    _operationType = operationType;

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageStickerPackOperationType operationType;
    switch (self.operationType) {
        case StickerPackOperationType_Install:
            operationType = SSKProtoSyncMessageStickerPackOperationTypeInstall;
            break;
        case StickerPackOperationType_Remove:
            operationType = SSKProtoSyncMessageStickerPackOperationTypeRemove;
            break;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    for (StickerPackInfo *pack in self.packs) {
        SSKProtoSyncMessageStickerPackOperationBuilder *packOperationBuilder =
            [SSKProtoSyncMessageStickerPackOperation builderWithPackID:pack.packId packKey:pack.packKey];
        [packOperationBuilder setType:operationType];

        NSError *error;
        SSKProtoSyncMessageStickerPackOperation *_Nullable packOperationProto =
            [packOperationBuilder buildAndReturnError:&error];
        if (error || !packOperationProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [syncMessageBuilder addStickerPackOperation:packOperationProto];
    }

    return syncMessageBuilder;
}

- (BOOL)isUrgent
{
    return NO;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
