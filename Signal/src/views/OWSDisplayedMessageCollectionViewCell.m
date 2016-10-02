//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisplayedMessageCollectionViewCell.h"

#import <JSQMessagesViewController/UIView+JSQMessages.h>

const CGFloat OWSDisplayedMessageCellMinimumHeight = 70.0;

@interface OWSDisplayedMessageCollectionViewCell ()

@property (weak, nonatomic) IBOutlet JSQMessagesLabel *cellLabel;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *cellTopLabelHeightConstraint;
@property (weak, nonatomic) IBOutlet UIImageView *headerImageView;

@end

@implementation OWSDisplayedMessageCollectionViewCell

#pragma mark - Class Methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([self class]) bundle:[NSBundle mainBundle]];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

#pragma mark - Initializer

- (void)awakeFromNib
{
    [super awakeFromNib];

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.backgroundColor = [UIColor whiteColor];

    self.messageBubbleContainerView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.messageBubbleContainerView.layer.borderWidth = 0.75f;
    self.messageBubbleContainerView.layer.cornerRadius = 5.0f;
    self.cellLabel.textColor = [UIColor darkGrayColor];
}

#pragma mark - Collection view cell

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.cellLabel.text = nil;
}

@end
