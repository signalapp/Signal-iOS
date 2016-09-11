//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "TSMessageAdapter.h"

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

    TSMessageAdapter *message = (TSMessageAdapter *)messageData;
    if (message.messageType == TSInfoMessageAdapter || message.messageType == TSErrorMessageAdapter) {
        // Prevent cropping message text by accounting for message container/icon
        // But also allow for multi-line error messages.
        superSize.height = fmax(superSize.height, OWSDisplayedMessageCellHeight);
    }

    return superSize;
}

@end
