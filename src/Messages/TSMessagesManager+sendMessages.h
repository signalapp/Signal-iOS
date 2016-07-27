//
//  TSMessagesManager+sendMessages.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"

@class SignalRecipient;

@interface TSMessagesManager (sendMessages)

typedef void (^successSendingCompletionBlock)();
typedef void (^failedSendingCompletionBlock)();

- (void)sendMessage:(TSOutgoingMessage *)message
           inThread:(TSThread *)thread
            success:(successSendingCompletionBlock)successCompletionBlock
            failure:(failedSendingCompletionBlock)failedCompletionBlock;

- (void)resendMessage:(TSOutgoingMessage *)message
          toRecipient:(SignalRecipient *)recipient
             inThread:(TSThread *)thread
              success:(successSendingCompletionBlock)successCompletionBlock
              failure:(failedSendingCompletionBlock)failedCompletionBlock;

@end
