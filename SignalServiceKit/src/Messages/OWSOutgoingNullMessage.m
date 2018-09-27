//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingNullMessage.h"
#import "Cryptography.h"
#import "NSDate+OWS.h"
#import "OWSVerificationStateSyncMessage.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingNullMessage ()

@property (nonatomic, readonly) OWSVerificationStateSyncMessage *verificationStateSyncMessage;

@end

#pragma mark -

@implementation OWSOutgoingNullMessage

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage
{
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:contactThread
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
    
    _verificationStateSyncMessage = verificationStateSyncMessage;
    
    return self;
}

#pragma mark - override TSOutgoingMessage

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    SSKProtoNullMessageBuilder *nullMessageBuilder = [SSKProtoNullMessageBuilder new];

    NSUInteger contentLength = self.verificationStateSyncMessage.unpaddedVerifiedLength;

    OWSAssertDebug(self.verificationStateSyncMessage.paddingBytesLength > 0);

    // We add the same amount of padding in the VerificationStateSync message and it's coresponding NullMessage so that
    // the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage. We pad
    // the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be *additionally*
    // padded by the superclass while being sent. The end result is we send a NullMessage of a non-distinct size, and a
    // verification sync which is ~1-512 bytes larger then that.
    contentLength += self.verificationStateSyncMessage.paddingBytesLength;

    OWSAssertDebug(contentLength > 0);

    nullMessageBuilder.padding = [Cryptography generateRandomBytes:contentLength];

    NSError *error;
    SSKProtoNullMessage *_Nullable nullMessage = [nullMessageBuilder buildAndReturnError:&error];
    if (error || !nullMessage) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
    contentBuilder.nullMessage = nullMessage;

    NSData *_Nullable contentData = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error || !contentData) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return contentData;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
