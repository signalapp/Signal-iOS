//  Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import <JSQMessagesViewController/JSQMessagesBubblesSizeCalculator.h>

NS_SWIFT_NAME(MessagesBubblesSizeCalculator)
@interface OWSMessagesBubblesSizeCalculator : JSQMessagesBubblesSizeCalculator

- (CGSize)messageBubbleSizeForMessageData:(id<JSQMessageData>)messageData
                              atIndexPath:(NSIndexPath *)indexPath
                               withLayout:(JSQMessagesCollectionViewFlowLayout *)layout;

@end
