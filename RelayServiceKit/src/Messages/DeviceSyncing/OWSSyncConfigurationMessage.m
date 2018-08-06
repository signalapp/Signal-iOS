//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncConfigurationMessage.h"
#import "OWSSignalServiceProtos.pb.h"

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

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{

    OWSSignalServiceProtosSyncMessageConfigurationBuilder *configurationBuilder =
        [OWSSignalServiceProtosSyncMessageConfigurationBuilder new];
    configurationBuilder.readReceipts = self.areReadReceiptsEnabled;

    OWSSignalServiceProtosSyncMessageBuilder *builder = [OWSSignalServiceProtosSyncMessageBuilder new];

    builder.configurationBuilder = configurationBuilder;

    return builder;
}

@end

NS_ASSUME_NONNULL_END
