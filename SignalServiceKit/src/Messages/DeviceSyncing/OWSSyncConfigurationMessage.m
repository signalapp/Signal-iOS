//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncConfigurationMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage ()

@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;
@property (nonatomic, readonly) BOOL showUnidentifiedDeliveryIndicators;
@property (nonatomic, readonly) BOOL showTypingIndicators;
@property (nonatomic, readonly) BOOL sendLinkPreviews;

@end

@implementation OWSSyncConfigurationMessage

- (instancetype)initWithThread:(TSThread *)thread
                   readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
    showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                  showTypingIndicators:(BOOL)showTypingIndicators
                      sendLinkPreviews:(BOOL)sendLinkPreviews
                           transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return nil;
    }

    _areReadReceiptsEnabled = areReadReceiptsEnabled;
    _showUnidentifiedDeliveryIndicators = showUnidentifiedDeliveryIndicators;
    _showTypingIndicators = showTypingIndicators;
    _sendLinkPreviews = sendLinkPreviews;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageConfigurationBuilder *configurationBuilder = [SSKProtoSyncMessageConfiguration builder];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;
    configurationBuilder.unidentifiedDeliveryIndicators = self.showUnidentifiedDeliveryIndicators;
    configurationBuilder.typingIndicators = self.showTypingIndicators;
    configurationBuilder.linkPreviews = self.sendLinkPreviews;
    configurationBuilder.provisioningVersion = OWSDeviceProvisioner.provisioningVersion;

    NSError *error;
    SSKProtoSyncMessageConfiguration *_Nullable configurationProto = [configurationBuilder buildAndReturnError:&error];
    if (error || !configurationProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessage builder];
    builder.configuration = configurationProto;
    return builder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
