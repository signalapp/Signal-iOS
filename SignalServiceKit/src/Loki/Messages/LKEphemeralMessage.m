#import "LKEphemeralMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>

@implementation LKEphemeralMessage

+ (LKEphemeralMessage *)createEmptyOutgoingMessageInThread:(TSThread *)thread {
    return [[LKEphemeralMessage alloc] initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
