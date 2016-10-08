//  Created by Dylan Bourgeois on 20/11/14.
//  Portions Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSCallCollectionViewCell.h"
#import "UIColor+OWS.h"
#import <JSQMessagesViewController/JSQMessagesCollectionViewLayoutAttributes.h>
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
    self.textView.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:12.0f];

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
}

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes
{
    // override superclass with no-op which resets our attributed font on layout.
}

@end
