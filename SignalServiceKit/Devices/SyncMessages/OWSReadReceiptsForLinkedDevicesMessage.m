//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSReadReceiptsForLinkedDevicesMessage.h"
#import "OWSLinkedDeviceReadReceipt.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsForLinkedDevicesMessage ()

@property (nonatomic, readonly) NSArray<OWSLinkedDeviceReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsForLinkedDevicesMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                       readReceipts:(NSArray<OWSLinkedDeviceReadReceipt *> *)readReceipts
                        transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSArray *readReceipts = self.readReceipts;
    if (readReceipts != nil) {
        [coder encodeObject:readReceipts forKey:@"readReceipts"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_readReceipts =
        [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [OWSLinkedDeviceReadReceipt class] ]]
                              forKey:@"readReceipts"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.readReceipts.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSReadReceiptsForLinkedDevicesMessage *typedOther = (OWSReadReceiptsForLinkedDevicesMessage *)other;
    if (![NSObject isObject:self.readReceipts equalToObject:typedOther.readReceipts]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSReadReceiptsForLinkedDevicesMessage *result = [super copyWithZone:zone];
    result->_readReceipts = self.readReceipts;
    return result;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    for (OWSLinkedDeviceReadReceipt *readReceipt in self.readReceipts) {
        SSKProtoSyncMessageReadBuilder *readProtoBuilder =
            [SSKProtoSyncMessageRead builderWithTimestamp:readReceipt.messageIdTimestamp];

        ServiceIdObjC *aciObj = readReceipt.senderAddress.serviceIdObjC;
        if ([aciObj isKindOfClass:[AciObjC class]]) {
            if (BuildFlagsObjC.serviceIdStrings) {
                [readProtoBuilder setSenderAci:aciObj.serviceIdString];
            }
            if (BuildFlagsObjC.serviceIdBinaryVariableOverhead) {
                [readProtoBuilder setSenderAciBinary:aciObj.serviceIdBinary];
            }
        } else {
            OWSFailDebug(@"can't send read receipt for message without an ACI");
        }

        NSError *error;
        SSKProtoSyncMessageRead *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
        if (error || !readProto) {
            OWSFailDebug(@"could not build protobuf: %@", error);
            return nil;
        }
        [syncMessageBuilder addRead:readProto];
    }
    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    NSMutableArray<NSString *> *messageUniqueIds = [[NSMutableArray alloc] init];
    for (OWSLinkedDeviceReadReceipt *readReceipt in self.readReceipts) {
        if (readReceipt.messageUniqueId) {
            [messageUniqueIds addObject:readReceipt.messageUniqueId];
        }
    }
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:messageUniqueIds];
}


@end

NS_ASSUME_NONNULL_END
