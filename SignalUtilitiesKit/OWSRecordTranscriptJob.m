//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSRecordTranscriptJob.h"
#import "OWSAttachmentDownloads.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSReadReceiptManager.h"
#import "SSKEnvironment.h"
#import "TSAttachmentPointer.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import "OWSPrimaryStorage+Loki.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRecordTranscriptJob

#pragma mark - Dependencies

+ (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

+ (OWSReadReceiptManager *)readReceiptManager
{
    OWSAssert(SSKEnvironment.shared.readReceiptManager);

    return SSKEnvironment.shared.readReceiptManager;
}

#pragma mark -

+ (void)processIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                    serverID:(uint64_t)serverID
                             serverTimestamp:(uint64_t)serverTimestamp
                           attachmentHandler:(void (^)(
                                                 NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    
}

#pragma mark -

+ (void)processRecipientUpdateWithTranscript:(OWSIncomingSentMessageTranscript *)transcript
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    
}

@end

NS_ASSUME_NONNULL_END
