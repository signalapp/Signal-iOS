//  Created by Dylan Bourgeois on 20/11/14.
//  Portions Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import <UIKit/UIKit.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>

@interface OWSCallCollectionViewCell : JSQMessagesCollectionViewCell

@property (weak, nonatomic, readonly) JSQMessagesLabel *cellLabel;
@property (weak, nonatomic, readonly) UIImageView *outgoingCallImageView;
@property (weak, nonatomic, readonly) UIImageView *incomingCallImageView;

#pragma mark - Class methods

+ (UINib *)nib;
+ (NSString *)cellReuseIdentifier;

@end
