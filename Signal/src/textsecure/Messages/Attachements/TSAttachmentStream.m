//
//  TSattachmentStream.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "UIImage+contentTypes.h"
#import <AVFoundation/AVFoundation.h>

NSString * const TSAttachementFileRelationshipEdge = @"TSAttachementFileEdge";

@implementation TSAttachmentStream

- (instancetype)initWithIdentifier:(NSString*)identifier
                              data:(NSData*)data
                               key:(NSData*)key
                       contentType:(NSString*)contentType {
    self = [super initWithIdentifier:identifier encryptionKey:key contentType:contentType];

    [[NSFileManager defaultManager] createFileAtPath:self.filePath contents:data attributes:nil];
    
    _isDownloaded = YES;
    return self;
}

- (NSArray *)yapDatabaseRelationshipEdges {
    YapDatabaseRelationshipEdge *attachmentFileEdge = [YapDatabaseRelationshipEdge edgeWithName:TSAttachementFileRelationshipEdge
                                                                            destinationFilePath:[self filePath]
                                                                                nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
    
    return @[attachmentFileEdge];
}

+ (NSString*)attachmentsFolder {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL *fileURL             = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *path             = [fileURL path];
    NSString *attachmentFolder = [path stringByAppendingFormat:@"/Attachments"];
    
    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:attachmentFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
        DDLogError(@"Failed to create attachments directory: %@", error.description);
    }
    
    return attachmentFolder;
}

- (NSString*)filePath {
    if ([self isVideo] || [self isAudio]) {
        return [[[[self class] attachmentsFolder] stringByAppendingFormat:@"/%@", self.uniqueId] stringByAppendingPathExtension:[self mediaExtension]];

    }
    else {
        return [[[self class] attachmentsFolder] stringByAppendingFormat:@"/%@", self.uniqueId];
    }
}

-(NSURL*) mediaURL {
    return [NSURL fileURLWithPath:[self filePath]];
}

- (BOOL)isImage {
    return [self.contentType containsString:@"image/"];
}

-(NSString*)mediaExtension {
    return [[self.contentType stringByReplacingOccurrencesOfString:@"video/" withString:@""] stringByReplacingOccurrencesOfString:@"audio/" withString:@""];
}

- (BOOL)isVideo {
    return [self.contentType containsString:@"video/"];
}

-(BOOL)isAudio {
    return [self.contentType containsString:@"audio/"];
}

- (UIImage*)image {
    if (![self isImage]) {
        return [self videoThumbnail];
    }

    return [UIImage imageWithContentsOfFile:self.filePath];
}


- (UIImage*)videoThumbnail {
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:self.filePath] options:nil];
    AVAssetImageGenerator *generate = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    NSError *err = NULL;
    CMTime time = CMTimeMake(1, 60);
    CGImageRef imgRef = [generate copyCGImageAtTime:time actualTime:NULL error:&err];
    return [[UIImage alloc] initWithCGImage:imgRef];
    
}

+ (void)deleteAttachments {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    [fm removeItemAtPath:[self attachmentsFolder] error:&error];
    if (error) {
        DDLogError(@"Failed to delete attachment folder with error: %@", error.debugDescription);
    }
}

@end
