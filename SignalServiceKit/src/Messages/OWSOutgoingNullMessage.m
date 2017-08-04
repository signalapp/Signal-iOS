//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingNullMessage.h"
#import "Cryptography.h"
#import "NSDate+millisecondTimeStamp.h"
#import "TSContactThread.h"
#import "OWSSignalServiceProtos.pb.h"
#import "OWSVerificationStateSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingNullMessage ()

@property (nonatomic, readonly) OWSVerificationStateSyncMessage *verificationStateSyncMessage;

@end

@implementation OWSOutgoingNullMessage

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                           inThread:contactThread];
    if (!self) {
        return self;
    }
    
    _verificationStateSyncMessage = verificationStateSyncMessage;
    
    return self;
}

#pragma mark - override TSOutgoingMessage

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    OWSSignalServiceProtosNullMessageBuilder *nullMessageBuilder = [OWSSignalServiceProtosNullMessageBuilder new];

    NSUInteger contentLength = self.verificationStateSyncMessage.unpaddedVerifiedLength;

    OWSAssert(self.verificationStateSyncMessage.paddingBytesLength > 0);

    // We add the same amount of padding in the VerificationStateSync message and it's coresponding NullMessage so that
    // the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage. We pad
    // the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be *additionally*
    // padded by the superclass while being sent. The end result is we send a NullMessage of a non-distinct size, and a
    // verification sync which is ~1-512 bytes larger then that.
    contentLength += self.verificationStateSyncMessage.paddingBytesLength;

    OWSAssert(contentLength > 0)
    
    nullMessageBuilder.padding = [Cryptography generateRandomBytes:contentLength];
    
    contentBuilder.nullMessage = [nullMessageBuilder build];

    [self addLocalProfileKeyIfNecessary:contentBuilder recipient:recipient];

    return [contentBuilder build].data;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // No-op as we don't want to actually display this as an outgoing message in our thread.
    return;
}

@end

NS_ASSUME_NONNULL_END
