//
//  JSQDisplayedMessageCollectionViewCell.h
//  JSQMessages
//
//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>

static const CGFloat OWSDisplayedMessageCellHeight = 70.0f;

@interface JSQDisplayedMessageCollectionViewCell : JSQMessagesCollectionViewCell

// TODO can we use existing label from superclass?
@property (weak, nonatomic, readonly) JSQMessagesLabel * cellLabel;
@property (weak, nonatomic, readonly) UIImageView * headerImageView;
@property (strong, nonatomic, readonly) UIView *textContainer;

@end
