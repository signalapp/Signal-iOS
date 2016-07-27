//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NSString *const TSAttachementFileRelationshipEdge = @"TSAttachementFileEdge";

@implementation TSAttachmentStream

- (instancetype)initWithIdentifier:(NSString *)identifier
                              data:(NSData *)data
                               key:(NSData *)key
                       contentType:(NSString *)contentType
{
    self = [super initWithIdentifier:identifier encryptionKey:key contentType:contentType];
    if (!self) {
        return self;
    }

    [[NSFileManager defaultManager] createFileAtPath:[self filePath] contents:data attributes:nil];
    DDLogInfo(@"Created file at %@", [self filePath]);
    _isDownloaded = YES;

    return self;
}

- (NSArray *)yapDatabaseRelationshipEdges {
    YapDatabaseRelationshipEdge *attachmentFileEdge =
        [YapDatabaseRelationshipEdge edgeWithName:TSAttachementFileRelationshipEdge
                               destinationFileURL:[self mediaURL]
                                  nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];

    return @[ attachmentFileEdge ];
}

+ (NSString *)attachmentsFolder
{
    NSString *documentsPath =
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *attachmentFolder = [documentsPath stringByAppendingFormat:@"/Attachments"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:attachmentFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        DDLogError(@"Failed to create attachments directory: %@", error);
    }

    return attachmentFolder;
}

- (NSString *)filePath {
    return [MIMETypeUtil filePathForAttachment:self.uniqueId
                                    ofMIMEType:self.contentType
                                      inFolder:[[self class] attachmentsFolder]];
}

- (NSURL *)mediaURL {
    return [NSURL fileURLWithPath:[self filePath]];
}

- (BOOL)isAnimated {
    return [MIMETypeUtil isAnimated:self.contentType];
}

- (BOOL)isImage {
    return [MIMETypeUtil isImage:self.contentType];
}

- (BOOL)isVideo {
    return [MIMETypeUtil isVideo:self.contentType];
}

- (BOOL)isAudio {
    return [MIMETypeUtil isAudio:self.contentType];
}

- (UIImage *)image {
    if ([self isVideo] || [self isAudio]) {
        return [self videoThumbnail];
    } else {
        // [self isAnimated] || [self isImage]
        return [UIImage imageWithData:[NSData dataWithContentsOfURL:[self mediaURL]]];
    }
}

- (UIImage *)videoThumbnail {
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:self.filePath] options:nil];
    AVAssetImageGenerator *generate         = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generate.appliesPreferredTrackTransform = YES;
    NSError *err                            = NULL;
    CMTime time                             = CMTimeMake(1, 60);
    CGImageRef imgRef                       = [generate copyCGImageAtTime:time actualTime:NULL error:&err];
    return [[UIImage alloc] initWithCGImage:imgRef];
}

+ (void)deleteAttachments
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self attachmentsFolder] error:&error];
    if (error) {
        DDLogError(@"Failed to delete attachment folder with error: %@", error.debugDescription);
    }
}

@end
