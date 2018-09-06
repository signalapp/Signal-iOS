//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDynamicOutgoingMessage.h"
#import "NSDate+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDynamicOutgoingMessage ()

@property (nonatomic, readonly) DynamicOutgoingMessageBlock block;

@end

#pragma mark -

@implementation OWSDynamicOutgoingMessage

- (instancetype)initWithPlainTextDataBlock:(DynamicOutgoingMessageBlock)block thread:(nullable TSThread *)thread
{
    return [self initWithPlainTextDataBlock:block timestamp:[NSDate ows_millisecondTimeStamp] thread:thread];
}

- (instancetype)initWithPlainTextDataBlock:(DynamicOutgoingMessageBlock)block
                                 timestamp:(uint64_t)timestamp
                                    thread:(nullable TSThread *)thread
{
    self = [super initOutgoingMessageWithTimestamp:timestamp
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];

    if (self) {
        _block = block;
    }

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    NSData *plainTextData = self.block(recipient);
    OWSAssertDebug(plainTextData);
    return plainTextData;
}

@end

NS_ASSUME_NONNULL_END
