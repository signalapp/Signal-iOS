//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

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

// This should be invoked by the main app when the app is ready.
- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
