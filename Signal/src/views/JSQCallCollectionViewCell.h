//
//  JSQCallCollectionViewCell.h
//  JSQMessages
//
//  Created by Dylan Bourgeois on 20/11/14.
//

#import <UIKit/UIKit.h>

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>

#define kCallCellHeight 40.0f
#define kCallCellWidth 400.0f

@interface JSQCallCollectionViewCell : JSQMessagesCollectionViewCell

// TODO can we use an existing label from JSQMessagesCollectionViewCell?
@property (weak, nonatomic, readonly) JSQMessagesLabel *cellLabel;

@property (weak, nonatomic, readonly) UIImageView *outgoingCallImageView;

@property (weak, nonatomic, readonly) UIImageView *incomingCallImageView;


#pragma mark - Class methods

+ (UINib *)nib;

+ (NSString *)cellReuseIdentifier;

@end
