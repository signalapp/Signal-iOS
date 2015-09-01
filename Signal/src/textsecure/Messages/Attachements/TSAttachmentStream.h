//
//  TSAttachementStream.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"

@interface TSAttachmentStream : TSAttachment <YapDatabaseRelationshipNode>

@property (nonatomic) BOOL isDownloaded;

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType NS_DESIGNATED_INITIALIZER;;

- (UIImage *)image;

- (BOOL)isAnimated;
- (BOOL)isImage;
- (BOOL)isVideo;
-(NSURL*)mediaURL;

+ (void)deleteAttachments;
+ (NSString*)attachmentsFolder;

@end
