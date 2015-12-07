//
//  TSOutgoingMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

@interface TSOutgoingMessage : TSMessage

typedef NS_ENUM(NSInteger, TSOutgoingMessageState) {
    TSOutgoingMessageStateAttemptingOut,
    TSOutgoingMessageStateUnsent,
    TSOutgoingMessageStateSent,
    TSOutgoingMessageStateDelivered
};

@property (nonatomic) TSOutgoingMessageState messageState;
@end
