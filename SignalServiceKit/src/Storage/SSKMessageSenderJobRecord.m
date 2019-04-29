//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKMessageSenderJobRecord.h"
#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SSKMessageSenderJobRecord

#pragma mark

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable instancetype)initWithMessage:(TSOutgoingMessage *)message
               removeMessageAfterSending:(BOOL)removeMessageAfterSending
                                   label:(NSString *)label
                                   error:(NSError **)outError
{
    self = [super initWithLabel:label];
    if (!self) {
        return self;
    }

    if (message.shouldBeSaved) {
        _messageId = message.uniqueId;
        if (_messageId == nil) {
            *outError = [NSError errorWithDomain:SSKJobRecordErrorDomain
                                            code:JobRecordError_AssertionError
                                        userInfo:@{ NSDebugDescriptionErrorKey : @"messageId wasn't set" }];
            return nil;
        }
        _invisibleMessage = nil;
    } else {
        _messageId = nil;
        _invisibleMessage = message;
    }

    _removeMessageAfterSending = removeMessageAfterSending;
    _threadId = message.uniqueThreadId;

    return self;
}

@end

NS_ASSUME_NONNULL_END
