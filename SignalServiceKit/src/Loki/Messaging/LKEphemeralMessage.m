#import "LKEphemeralMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@implementation LKEphemeralMessage

- (instancetype)initInThread:(nullable TSThread *)thread {
    return [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

// An EphemeralMessage does not have any data message in the content
- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    NSError *error;
    SSKProtoContentBuilder *contentBuilder = [self contentBuilder:recipient];
    
    NSData *_Nullable contentData = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error || !contentData) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return contentData;
}

- (BOOL)shouldSyncTranscript { return NO; }
- (BOOL)shouldBeSaved { return NO; }

@end
