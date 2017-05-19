//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMediaItem.h>

@interface JSQMediaItem (OWS)

- (CGFloat)ows_maxMediaBubbleWidth:(CGSize)defaultBubbleSize;

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImage:(UIImage *)image;

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImageSize:(CGSize)imageSize;

- (CGSize)sizeOfImageAtURL:(NSURL *)imageURL;

@end
