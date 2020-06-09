#import "LKEphemeralMessage.h"
#import <SessionCoreKit/NSDate+OWS.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>

@implementation LKEphemeralMessage

#pragma mark Initialization
- (instancetype)initInThread:(nullable TSThread *)thread {
    return [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

#pragma mark Settings
- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }
- (uint)ttl { return (uint)[LKTTLUtilities getTTLFor:LKMessageTypeEphemeral]; }

@end
