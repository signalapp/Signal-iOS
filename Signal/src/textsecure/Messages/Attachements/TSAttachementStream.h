//
//  TSAttachementStream.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachement.h"

@interface TSAttachementStream : TSAttachement

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType;

- (NSString*)path;

- (BOOL)isImage;
- (UIImage*)image;

- (BOOL)isVideo;

@end
