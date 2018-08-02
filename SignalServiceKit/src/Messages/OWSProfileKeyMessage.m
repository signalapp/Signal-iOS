//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileKeyMessage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import "TextSecureKitEnv.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSProfileKeyMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread
{
    return [super initOutgoingMessageWithTimestamp:timestamp
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId
{
    OWSAssert(self.thread);

    SSKProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilder];
    if (!builder) {
        OWSFail(@"%@ could not build protobuf.", self.logTag);
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [ProtoUtils addLocalProfileKeyToDataMessageBuilder:builder];
    [builder setFlags:SSKProtoDataMessageFlagsProfileKeyUpdate];
    
    if (recipientId.length > 0) {
        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
        [profileManager addUserToProfileWhitelist:recipientId];
    }

    NSError *error;
    SSKProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error || !dataProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return dataProto;
}

@end

NS_ASSUME_NONNULL_END
