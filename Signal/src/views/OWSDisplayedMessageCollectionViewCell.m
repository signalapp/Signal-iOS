//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisplayedMessageCollectionViewCell.h"

#import <JSQMessagesViewController/UIView+JSQMessages.h>

@interface OWSDisplayedMessageCollectionViewCell ()

@property (weak, nonatomic) IBOutlet JSQMessagesLabel *cellLabel;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *cellTopLabelHeightConstraint;
@property (weak, nonatomic) IBOutlet UIImageView *headerImageView;
@property (strong, nonatomic) IBOutlet UIView *textContainer;

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

    self.textContainer.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.textContainer.layer.borderWidth = 0.75f;
    self.textContainer.layer.cornerRadius = 5.0f;
    self.cellLabel.textAlignment = NSTextAlignmentCenter;
    self.cellLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:14.0f];
    self.cellLabel.textColor = [UIColor lightGrayColor];
}

#pragma mark - Collection view cell

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.cellLabel.text = nil;
}

@end
