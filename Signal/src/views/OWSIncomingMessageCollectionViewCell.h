//  Created by Michael Kirk on 9/29/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSExpirableMessageView.h"
#import <JSQMessagesViewController/JSQMessagesCollectionViewCellIncoming.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSIncomingMessageCollectionViewCell : JSQMessagesCollectionViewCellIncoming <OWSExpirableMessageView>

@end

NS_ASSUME_NONNULL_END
