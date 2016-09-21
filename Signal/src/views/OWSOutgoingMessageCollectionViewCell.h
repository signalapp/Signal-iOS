//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSExpirableMessageView.h"
#import <JSQMessagesViewController/JSQMessagesCollectionViewCellOutgoing.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingMessageCollectionViewCell : JSQMessagesCollectionViewCellOutgoing <OWSExpirableMessageView>


@end

NS_ASSUME_NONNULL_END
