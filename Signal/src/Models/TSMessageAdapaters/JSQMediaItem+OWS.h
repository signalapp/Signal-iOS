//
//  JSQMediaItem+OWS.h
//  Signal
//
//  Created by Matthew Douglass on 10/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMediaItem.h>

@interface JSQMediaItem (OWS)

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImage:(UIImage *)image;

@end
