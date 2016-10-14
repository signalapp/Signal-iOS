//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import "TSAttachmentPointer.h"
#import <AVFoundation/AVFoundation.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TSAttachmentStream

- (instancetype)initWithContentType:(NSString *)contentType
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contentType = contentType;
    _isDownloaded = YES;

    return self;
}

- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer
{
    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithUniqueId:pointer.uniqueId];
    if (!self) {
        return self;
    }

    _contentType = pointer.contentType;
    _isDownloaded = YES;

    return self;
}

#pragma mark - TSYapDatabaseModel overrides

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];
    [self removeFile];
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    return [NSData dataWithContentsOfFile:self.filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    DDLogInfo(@"%@ Created file at %@", self.tag, self.filePath);
    return [data writeToFile:self.filePath options:0 error:error];
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

+ (NSUInteger)numberOfItemsInAttachmentsFolder
{
    NSError *error;
    NSUInteger count =
        [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self attachmentsFolder] error:&error] count];

    if (error) {
        DDLogError(@"Unable to count attachments in attachments folder. Error: %@", error);
    }

    return count;
}

- (nullable NSString *)filePath
{
    return [MIMETypeUtil filePathForAttachment:self.uniqueId
                                    ofMIMEType:self.contentType
                                      inFolder:[[self class] attachmentsFolder]];
}

- (nullable NSURL *)mediaURL
{
    NSString *filePath = self.filePath;
    return filePath ? [NSURL fileURLWithPath:filePath] : nil;
}

- (void)removeFile
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self filePath] error:&error];

    if (error) {
        DDLogError(@"%@ remove file errored with: %@", self.tag, error);
    }
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

- (nullable UIImage *)image
{
    if ([self isVideo] || [self isAudio]) {
        return [self videoThumbnail];
    } else {
        // [self isAnimated] || [self isImage]
        return [UIImage imageWithData:[NSData dataWithContentsOfURL:[self mediaURL]]];
    }
}

- (nullable UIImage *)videoThumbnail
{
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

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
