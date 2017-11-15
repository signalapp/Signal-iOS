//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsRequestMessage.h"
#import "NSDate+OWS.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncGroupsRequestMessage ()

@property (nonatomic) NSData *groupId;

@end

#pragma mark -

@implementation OWSSyncGroupsRequestMessage

- (instancetype)initWithThread:(nullable TSThread *)thread groupId:(NSData *)groupId
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];
    if (!self) {
        return self;
    }

    OWSAssert(groupId.length > 0);
    _groupId = groupId;

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)isSilent
{
    // Avoid "phantom messages"

    return YES;
}

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    OWSSignalServiceProtosGroupContextBuilder *groupContextBuilder = [OWSSignalServiceProtosGroupContextBuilder new];
    [groupContextBuilder setType:OWSSignalServiceProtosGroupContextTypeRequestInfo];
    [groupContextBuilder setId:self.groupId];

    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setGroupBuilder:groupContextBuilder];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
