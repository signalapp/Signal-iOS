#import "OWSEphemeralMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>

@implementation OWSEphemeralMessage

+ (OWSEphemeralMessage *)createEmptyOutgoingMessageInThread:(TSThread *)thread {
    return [[OWSEphemeralMessage alloc] initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

- (BOOL)shouldBeSaved { return NO; }

@end
