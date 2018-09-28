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
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
    if (!self) {
        return self;
    }

    OWSAssertDebug(groupId.length > 0);
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
    SSKProtoGroupContextBuilder *groupContextBuilder =
        [[SSKProtoGroupContextBuilder alloc] initWithId:self.groupId type:SSKProtoGroupContextTypeRequestInfo];

    NSError *error;
    SSKProtoGroupContext *_Nullable groupContextProto = [groupContextBuilder buildAndReturnError:&error];
    if (error || !groupContextProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessageBuilder new];
    [builder setTimestamp:self.timestamp];
    [builder setGroup:groupContextProto];

    return builder;
}

@end

NS_ASSUME_NONNULL_END
