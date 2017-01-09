//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "JSQMessagesCollectionViewCell+OWS.h"
#import "OWSExpirableMessageView.h"
#import "MessageTextViewDelegate.h"
#import <JSQMessagesViewController/JSQMessagesCollectionViewCellOutgoing.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingMessageCollectionViewCell : JSQMessagesCollectionViewCellOutgoing <OWSExpirableMessageView>

@property (nonatomic, strong) MessageTextViewDelegate *textViewDelegate;

@end

NS_ASSUME_NONNULL_END
