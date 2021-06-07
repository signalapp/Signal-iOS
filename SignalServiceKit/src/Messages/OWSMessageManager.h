//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SSKProtoEnvelope;

@interface OWSMessageManager : OWSMessageHandler

// processEnvelope: can be called from any thread.
//
// Returns YES on success.
- (BOOL)processEnvelope:(SSKProtoEnvelope *)envelope
              plaintextData:(NSData *_Nullable)plaintextData
            wasReceivedByUD:(BOOL)wasReceivedByUD
    serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
