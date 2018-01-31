//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSEndSessionMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSEndSessionMessage

- (BOOL)shouldBeSaved
{
    return NO;
}

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    OWSSignalServiceProtosDataMessageBuilder *builder = [super dataMessageBuilder];
    [builder setTimestamp:self.timestamp];
    [builder setFlags:OWSSignalServiceProtosDataMessageFlagsEndSession];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
