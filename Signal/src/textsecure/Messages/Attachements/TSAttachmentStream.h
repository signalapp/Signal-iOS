//
//  TSAttachementStream.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"

@interface TSAttachmentStream : TSAttachment <YapDatabaseRelationshipNode>

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType NS_DESIGNATED_INITIALIZER;;

- (UIImage *)image;

- (BOOL)isImage;
- (BOOL)isVideo;

@end
