//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "TSMessageAdapter.h"
#import "tgmath.h" // generic math allows fmax to handle CGFLoat correctly on 32 & 64bit.

@implementation OWSMessagesBubblesSizeCalculator

/**
 *  Computes and returns the size of the `messageBubbleImageView` property
 *  of a `JSQMessagesCollectionViewCell` for the specified messageData at indexPath.
 *
 *  @param messageData A message data object.
 *  @param indexPath   The index path at which messageData is located.
 *  @param layout      The layout object asking for this information.
 *
 *  @return A sizes that specifies the required dimensions to display the entire message contents.
 *  Note, this is *not* the entire cell, but only its message bubble.
 */
- (CGSize)messageBubbleSizeForMessageData:(id<JSQMessageData>)messageData
                              atIndexPath:(NSIndexPath *)indexPath
                               withLayout:(JSQMessagesCollectionViewFlowLayout *)layout
{
    CGSize superSize = [super messageBubbleSizeForMessageData:messageData atIndexPath:indexPath withLayout:layout];

    if ([messageData isKindOfClass:[TSMessageAdapter class]]) {
        TSMessageAdapter *message = (TSMessageAdapter *)messageData;

        if (message.messageType == TSInfoMessageAdapter || message.messageType == TSErrorMessageAdapter) {
            // One-line error messages feel a little cramped, but multiline are OK as is.
            superSize.height = fmax(superSize.height, OWSDisplayedMessageCellMinimumHeight);
        }
    }

    return superSize;
}

@end
