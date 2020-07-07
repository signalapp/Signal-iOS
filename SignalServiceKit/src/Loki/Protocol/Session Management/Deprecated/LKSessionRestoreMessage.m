#import "LKSessionRestoreMessage.h"
#import <SessionCoreKit/NSDate+OWS.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>

@implementation LKSessionRestoreMessage

#pragma mark Initialization
- (instancetype)initWithThread:(TSThread *)thread {
    return [self initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:@"" attachmentIds:[NSMutableArray<NSString *> new]
        expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
}

#pragma mark Building
- (nullable id)dataMessageBuilder
{
    SSKProtoDataMessageBuilder *builder = super.dataMessageBuilder;
    if (builder == nil) { return nil; }
    [builder setFlags:SSKProtoDataMessageFlagsSessionRestore];
    return builder;
}

@end
