//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

extern const CGFloat OWSDisplayedMessageCellMinimumHeight;

@interface OWSDisplayedMessageCollectionViewCell : JSQMessagesCollectionViewCell

@property (weak, nonatomic, readonly) JSQMessagesLabel *cellLabel;
@property (weak, nonatomic, readonly) UIImageView *headerImageView;

@end
