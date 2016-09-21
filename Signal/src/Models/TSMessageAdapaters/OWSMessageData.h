//  Created by Michael Kirk on 9/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQMessageData.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSMessageAdapterType) {
    TSIncomingMessageAdapter,
    TSOutgoingMessageAdapter,
    TSCallAdapter,
    TSInfoMessageAdapter,
    TSErrorMessageAdapter,
    TSMediaAttachmentAdapter,
    TSGenericTextMessageAdapter, // Used when message direction is unknown (outgoing or incoming)
};

@protocol OWSMessageData <JSQMessageData, OWSMessageEditing>

@property (nonatomic, readonly) TSMessageAdapterType messageType;
@property (nonatomic, readonly, getter=isExpiringMessage) BOOL expiringMessage;
@property (nonatomic, readonly) uint64_t expiresAtSeconds;
@property (nonatomic, readonly) uint32_t expiresInSeconds;

@end

NS_ASSUME_NONNULL_END
