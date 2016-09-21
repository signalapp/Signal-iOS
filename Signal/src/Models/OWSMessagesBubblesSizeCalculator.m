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
            // DDLogVerbose(@"[OWSMessagesBubblesSizeCalculator] superSize.height:%f, superSize.width:%f",
            //     superSize.height,
            //     superSize.width);

            // header icon hangs ouside of the frame a bit.
            CGFloat headerIconProtrusion = 30.0f; // too  much padding with normal font.
            // CGFloat headerIconProtrusion = 18.0f; // clips
            superSize.height = superSize.height + headerIconProtrusion;
        }
    }

    return superSize;
}

@end
