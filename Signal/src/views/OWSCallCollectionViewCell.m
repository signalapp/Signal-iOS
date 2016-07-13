//  Created by Dylan Bourgeois on 20/11/14.
//  Portions Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSCallCollectionViewCell.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>

@interface OWSCallCollectionViewCell ()

@property (weak, nonatomic) IBOutlet JSQMessagesLabel *cellLabel;
@property (weak, nonatomic) IBOutlet UIImageView *outgoingCallImageView;
@property (weak, nonatomic) IBOutlet UIImageView *incomingCallImageView;

@end

@implementation OWSCallCollectionViewCell

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
