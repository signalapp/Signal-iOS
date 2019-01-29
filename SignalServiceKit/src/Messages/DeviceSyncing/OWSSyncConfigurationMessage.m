//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

- (instancetype)initWithReadReceiptsEnabled:(BOOL)areReadReceiptsEnabled
         showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                       showTypingIndicators:(BOOL)showTypingIndicators
                           sendLinkPreviews:(BOOL)sendLinkPreviews
{
    self = [super init];
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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageConfigurationBuilder *configurationBuilder = [SSKProtoSyncMessageConfiguration builder];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;
    configurationBuilder.unidentifiedDeliveryIndicators = self.showUnidentifiedDeliveryIndicators;
    configurationBuilder.typingIndicators = self.showTypingIndicators;
    configurationBuilder.linkPreviews = self.sendLinkPreviews;

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

@end

NS_ASSUME_NONNULL_END
