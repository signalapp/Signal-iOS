//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncConfigurationMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage ()

@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;
@property (nonatomic, readonly) BOOL showUnidentifiedDeliveryIndicators;
@property (nonatomic, readonly) BOOL showTypingIndicators;
@property (nonatomic, readonly) BOOL sendLinkPreviews;
@property (nonatomic, readonly) uint32_t provisioningVersion;

@end

@implementation OWSSyncConfigurationMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                   readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
    showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                  showTypingIndicators:(BOOL)showTypingIndicators
                      sendLinkPreviews:(BOOL)sendLinkPreviews
                   provisioningVersion:(uint32_t)provisioningVersion
                           transaction:(DBReadTransaction *)transaction
{
    self = [super initWithLocalThread:localThread transaction:transaction];
    if (!self) {
        return nil;
    }

    _areReadReceiptsEnabled = areReadReceiptsEnabled;
    _showUnidentifiedDeliveryIndicators = showUnidentifiedDeliveryIndicators;
    _showTypingIndicators = showTypingIndicators;
    _sendLinkPreviews = sendLinkPreviews;
    _provisioningVersion = provisioningVersion;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeObject:[self valueForKey:@"areReadReceiptsEnabled"] forKey:@"areReadReceiptsEnabled"];
    [coder encodeObject:[self valueForKey:@"provisioningVersion"] forKey:@"provisioningVersion"];
    [coder encodeObject:[self valueForKey:@"sendLinkPreviews"] forKey:@"sendLinkPreviews"];
    [coder encodeObject:[self valueForKey:@"showTypingIndicators"] forKey:@"showTypingIndicators"];
    [coder encodeObject:[self valueForKey:@"showUnidentifiedDeliveryIndicators"]
                 forKey:@"showUnidentifiedDeliveryIndicators"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_areReadReceiptsEnabled = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                     forKey:@"areReadReceiptsEnabled"] boolValue];
    self->_provisioningVersion = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                  forKey:@"provisioningVersion"] unsignedIntValue];
    self->_sendLinkPreviews = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                               forKey:@"sendLinkPreviews"] boolValue];
    self->_showTypingIndicators = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                   forKey:@"showTypingIndicators"] boolValue];
    self->_showUnidentifiedDeliveryIndicators =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                         forKey:@"showUnidentifiedDeliveryIndicators"] boolValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.areReadReceiptsEnabled;
    result ^= self.provisioningVersion;
    result ^= self.sendLinkPreviews;
    result ^= self.showTypingIndicators;
    result ^= self.showUnidentifiedDeliveryIndicators;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSSyncConfigurationMessage *typedOther = (OWSSyncConfigurationMessage *)other;
    if (self.areReadReceiptsEnabled != typedOther.areReadReceiptsEnabled) {
        return NO;
    }
    if (self.provisioningVersion != typedOther.provisioningVersion) {
        return NO;
    }
    if (self.sendLinkPreviews != typedOther.sendLinkPreviews) {
        return NO;
    }
    if (self.showTypingIndicators != typedOther.showTypingIndicators) {
        return NO;
    }
    if (self.showUnidentifiedDeliveryIndicators != typedOther.showUnidentifiedDeliveryIndicators) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSSyncConfigurationMessage *result = [super copyWithZone:zone];
    result->_areReadReceiptsEnabled = self.areReadReceiptsEnabled;
    result->_provisioningVersion = self.provisioningVersion;
    result->_sendLinkPreviews = self.sendLinkPreviews;
    result->_showTypingIndicators = self.showTypingIndicators;
    result->_showUnidentifiedDeliveryIndicators = self.showUnidentifiedDeliveryIndicators;
    return result;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    SSKProtoSyncMessageConfigurationBuilder *configurationBuilder = [SSKProtoSyncMessageConfiguration builder];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;
    configurationBuilder.unidentifiedDeliveryIndicators = self.showUnidentifiedDeliveryIndicators;
    configurationBuilder.typingIndicators = self.showTypingIndicators;
    configurationBuilder.linkPreviews = self.sendLinkPreviews;
    configurationBuilder.provisioningVersion = self.provisioningVersion;

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.configuration = [configurationBuilder buildInfallibly];
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
