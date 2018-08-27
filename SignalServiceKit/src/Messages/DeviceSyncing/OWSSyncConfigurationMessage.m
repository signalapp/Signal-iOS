//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncConfigurationMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage ()

@property (nonatomic, readonly) BOOL areReadReceiptsEnabled;

@end

@implementation OWSSyncConfigurationMessage

- (instancetype)initWithReadReceiptsEnabled:(BOOL)areReadReceiptsEnabled
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _areReadReceiptsEnabled = areReadReceiptsEnabled;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageConfigurationBuilder *configurationBuilder =
        [SSKProtoSyncMessageConfigurationBuilder new];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;

    NSError *error;
    SSKProtoSyncMessageConfiguration *_Nullable configurationProto = [configurationBuilder buildAndReturnError:&error];
    if (error || !configurationProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *builder = [SSKProtoSyncMessageBuilder new];
    builder.configuration = configurationProto;
    return builder;
}

@end

NS_ASSUME_NONNULL_END
