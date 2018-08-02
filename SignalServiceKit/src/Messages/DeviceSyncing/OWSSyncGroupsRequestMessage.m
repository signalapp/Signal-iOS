//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncGroupsRequestMessage.h"
#import "NSDate+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncGroupsRequestMessage ()

@property (nonatomic) NSData *groupId;

@end

#pragma mark -

@implementation OWSSyncGroupsRequestMessage

- (instancetype)initWithThread:(nullable TSThread *)thread groupId:(NSData *)groupId
{
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
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

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    SSKProtoGroupContextBuilder *groupContextBuilder = [SSKProtoGroupContextBuilder new];
    [groupContextBuilder setType:SSKProtoGroupContextTypeRequestInfo];
    [groupContextBuilder setId:self.groupId];

    NSError *error;
    SSKProtoGroupContext *_Nullable groupContextProto = [groupContextBuilder buildAndReturnError:&error];
    if (error || !groupContextProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessageBuilder new];
    [builder setTimestamp:self.timestamp];
    [builder setGroup:groupContextProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
