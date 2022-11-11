//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DataSource.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface DataSourceValue ()

@property (nonatomic) NSData *data;
@property (nonatomic) NSString *fileExtension;
@property (atomic) BOOL isConsumed;

// These properties is lazily-populated.
@property (nonatomic, nullable) NSURL *cachedFileUrl;
@property (nonatomic, nullable) ImageMetadata *cachedImageMetadata;

@end

#pragma mark -

@implementation DataSourceValue

- (void)dealloc
{
    NSURL *_Nullable fileUrl = self.cachedFileUrl;
    if (fileUrl != nil) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [OWSFileSystem deleteFileIfExists:fileUrl.path];
        });
    }
}

- (instancetype)initWithData:(NSData *)data
               fileExtension:(NSString *)fileExtension
{
    self = [super init];
    if (!self) {
        return self;
    }
    _data = data;
    _fileExtension = fileExtension;
    _isConsumed = NO;

    // Ensure that value is backed by file on disk.
    __weak DataSourceValue *weakValue = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakValue dataUrl];
    });

    return self;
}

+ (_Nullable id<DataSource>)dataSourceWithData:(NSData *)data
                                 fileExtension:(NSString *)fileExtension
{
    OWSAssertDebug(data);

    if (!data) {
        OWSFailDebug(@"data was unexpectedly nil");
        return nil;
    }

    return [[self alloc] initWithData:data fileExtension:fileExtension];
}

+ (_Nullable id<DataSource>)dataSourceWithData:(NSData *)data utiType:(NSString *)utiType
{
    NSString *fileExtension = [MIMETypeUtil fileExtensionForUTIType:utiType];
    return [[self alloc] initWithData:data fileExtension:fileExtension];
}

+ (_Nullable id<DataSource>)dataSourceWithOversizeText:(NSString *_Nullable)text
{
    if (!text) {
        return nil;
    }

    NSData *data = [text.filterStringForDisplay dataUsingEncoding:NSUTF8StringEncoding];
    return [[self alloc] initWithData:data fileExtension:kOversizeTextAttachmentFileExtension];
}

+ (id<DataSource>)emptyDataSource
{
    return [[self alloc] initWithData:[NSData new] fileExtension:@"bin"];
}

#pragma mark - DataSource

@synthesize sourceFilename = _sourceFilename;

- (void)setSourceFilename:(nullable NSString *)sourceFilename
{
    OWSAssertDebug(!self.isConsumed);
    _sourceFilename = sourceFilename.filterFilename;
}

- (nullable NSURL *)dataUrl
{
    OWSAssertDebug(self.data);
    OWSAssertDebug(!self.isConsumed);

    @synchronized(self)
    {
        if (!self.cachedFileUrl) {
            NSURL *fileUrl = [OWSFileSystem temporaryFileUrlWithFileExtension:self.fileExtension
                                                 isAvailableWhileDeviceLocked:YES];
            if ([self writeToUrl:fileUrl error:nil]) {
                self.cachedFileUrl = fileUrl;
            } else {
                OWSLogDebug(@"Could not write data to disk: %@", self.fileExtension);
                OWSFailDebug(@"Could not write data to disk.");
            }
        }

        return self.cachedFileUrl;
    }
}

- (NSUInteger)dataLength
{
    OWSAssertDebug(self.data);
    OWSAssertDebug(!self.isConsumed);
    return self.data.length;
}

- (BOOL)writeToUrl:(NSURL *)dstUrl error:(NSError **)outError
{
    OWSAssertDebug(self.data);
    OWSAssertDebug(!self.isConsumed);
    __block NSError *localError = nil;

    unsigned long long fileSize = self.dataLength;
    NSString *benchTitle = [NSString stringWithFormat:@"DataSourceValue writeData of size: %llu", fileSize];
    [BenchManager benchWithTitle:benchTitle
                           block:^{
                               BOOL success = [self.data writeToURL:dstUrl
                                                            options:NSDataWritingAtomic
                                                              error:&localError];
                               if (!success && !localError) {
                                   localError = OWSErrorMakeAssertionError(@"Could not write data source.");
                               }
                           }];
    if (localError != nil) {
        OWSLogDebug(@"Could not write data to disk: %@, %@", dstUrl, localError);
        OWSFailDebug(@"Could not write data to disk: %@", localError);
        if (outError != nil) {
            *outError = localError;
        }
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)moveToUrlAndConsume:(NSURL *)dstUrl error:(NSError **)outError
{
    OWSAssertDebug(!self.isConsumed);
    __block NSError *localError = nil;

    unsigned long long fileSize = self.dataLength;
    NSString *benchTitle = [NSString stringWithFormat:@"DataSourceValue moveItem with fileSize: %llu", fileSize];
    [BenchManager benchWithTitle:benchTitle
                           block:^{
                               @synchronized(self) {
                                   OWSAssertDebug(!NSThread.isMainThread);
                                   // This method is meant to be fast. If _cachedFileUrl is nil,
                                   // we'll still lazily generate it and this method will work,
                                   // but it will be slower than expected.
                                   OWSAssertDebug(self->_cachedFileUrl != nil);

                                   NSURL *_Nullable srcUrl = self.dataUrl;
                                   if (srcUrl == nil) {
                                       localError = OWSErrorMakeAssertionError(@"Missing data URL.");
                                       return;
                                   }
                                   self.isConsumed = YES;
                                   BOOL success = [OWSFileSystem moveFileFrom:srcUrl to:dstUrl error:&localError];
                                   if (!success && !localError) {
                                       localError = OWSErrorMakeAssertionError(@"Could not move data source.");
                                   }
                                   self->_cachedFileUrl = nil;
                               }
                           }];

    if (localError != nil) {
        OWSLogDebug(@"Could not write data value to: %@, %@", dstUrl, localError);
        OWSFailDebug(@"Could not write data with error: %@", localError);
        if (outError != nil) {
            *outError = localError;
        }
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)isValidImage
{
    OWSAssertDebug(!self.isConsumed);
    return [self.data ows_isValidImage];
}

- (BOOL)isValidVideo
{
    OWSAssertDebug(!self.isConsumed);
    if (![MIMETypeUtil isSupportedVideoFile:self.dataUrl.path]) {
        return NO;
    }
    OWSFailDebug(@"Are we calling this anywhere? It seems quite inefficient.");
    return [OWSMediaUtils isValidVideoWithPath:self.dataUrl.path];
}

- (nullable NSString *)mimeType
{
    OWSAssertDebug(!self.isConsumed);
    if (self.fileExtension == nil) {
        OWSFailDebug(@"failure: fileExtension was unexpectedly nil");
        return nil;
    }

    return [MIMETypeUtil mimeTypeForFileExtension:self.fileExtension];
}

- (BOOL)hasStickerLikeProperties
{
    OWSAssertDebug(!self.isConsumed);
    return [self.data ows_hasStickerLikeProperties];
}

- (ImageMetadata *)imageMetadata
{
    OWSAssertDebug(!self.isConsumed);

    @synchronized(self) {
        if (self.cachedImageMetadata != nil) {
            return self.cachedImageMetadata;
        }
        ImageMetadata *imageMetadata = [self.data imageMetadataWithPath:nil mimeType:self.mimeType ignoreFileSize:YES];
        self.cachedImageMetadata = imageMetadata;
        return imageMetadata;
    }
}

@end

#pragma mark -

@interface DataSourcePath ()

@property (nonatomic) NSURL *fileUrl;
@property (nonatomic, readonly) BOOL shouldDeleteOnDeallocation;
@property (atomic) BOOL isConsumed;

// These properties is lazily-populated.
@property (nonatomic) NSData *cachedData;
@property (nonatomic, nullable) ImageMetadata *cachedImageMetadata;

@end

#pragma mark -

@implementation DataSourcePath

- (void)dealloc
{
    if (self.shouldDeleteOnDeallocation && !self.isConsumed) {
        NSURL *fileUrl = self.fileUrl;
        if (!fileUrl) {
            OWSFailDebug(@"fileUrl was unexpectedly nil");
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error;
            BOOL success = [[NSFileManager defaultManager] removeItemAtURL:fileUrl error:&error];
            if (!success || error) {
                OWSCFailDebug(@"DataSourcePath could not delete file: %@, %@", fileUrl, error);
            }
        });
    }
}

- (nullable instancetype)initWithFileUrl:(NSURL *)fileUrl
              shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
                                   error:(NSError **)error
{
    if (!fileUrl || ![fileUrl isFileURL]) {
        NSString *errorMsg = [NSString stringWithFormat:@"unexpected fileUrl: %@", fileUrl];
        *error = OWSErrorMakeAssertionError(errorMsg);
        return nil;
    }

    self = [super init];
    if (!self) {
        return self;
    }

    _fileUrl = fileUrl;
    _shouldDeleteOnDeallocation = shouldDeleteOnDeallocation;
    _isConsumed = NO;

    return self;
}

+ (_Nullable id<DataSource>)dataSourceWithURL:(NSURL *)fileUrl
                   shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
                                        error:(NSError **)error
{
    return [[self alloc] initWithFileUrl:fileUrl
              shouldDeleteOnDeallocation:shouldDeleteOnDeallocation
                                   error:error];
}

+ (_Nullable id<DataSource>)dataSourceWithFilePath:(NSString *)filePath
                        shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
                                             error:(NSError **)error
{
    OWSAssertDebug(filePath);

    if (!filePath) {
        NSString *errorMsg = [NSString stringWithFormat:@"unexpected filePath: %@", filePath];
        *error = OWSErrorMakeAssertionError(errorMsg);
        return nil;
    }

    NSURL *fileUrl = [NSURL fileURLWithPath:filePath];
    return [[self alloc] initWithFileUrl:fileUrl
              shouldDeleteOnDeallocation:shouldDeleteOnDeallocation
                                   error:error];
}

+ (_Nullable id<DataSource>)dataSourceWritingTempFileData:(NSData *)data
                                            fileExtension:(NSString *)fileExtension
                                                    error:(NSError **)error
{
    NSURL *fileUrl = [OWSFileSystem temporaryFileUrlWithFileExtension:fileExtension isAvailableWhileDeviceLocked:YES];
    [data writeToURL:fileUrl options:NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error];
    if (*error != nil) {
        return nil;
    }
    return [[self alloc] initWithFileUrl:fileUrl shouldDeleteOnDeallocation:YES error:error];
}

+ (_Nullable id<DataSource>)dataSourceWritingSyncMessageData:(NSData *)data error:(NSError **)error
{
    return [self dataSourceWritingTempFileData:data fileExtension:kSyncMessageFileExtension error:error];
}

#pragma mark - DataSource

@synthesize sourceFilename = _sourceFilename;

- (void)setSourceFilename:(nullable NSString *)sourceFilename
{
    OWSAssertDebug(!self.isConsumed);
    _sourceFilename = sourceFilename.filterFilename;
}

- (NSData *)data
{
    OWSAssertDebug(!self.isConsumed);
    OWSAssertDebug(self.fileUrl);

    @synchronized(self)
    {
        if (!self.cachedData) {
            self.cachedData = [NSData dataWithContentsOfFile:self.fileUrl.path];
        }
        if (!self.cachedData) {
            OWSLogDebug(@"Could not read data from disk: %@", self.fileUrl);
            OWSFailDebug(@"Could not read data from disk.");
            self.cachedData = [NSData new];
        }
        return self.cachedData;
    }
}

- (NSUInteger)dataLength
{
    OWSAssertDebug(!self.isConsumed);
    OWSAssertDebug(self.fileUrl);

    NSNumber *fileSizeValue;
    NSError *error;
    [self.fileUrl getResourceValue:&fileSizeValue
                            forKey:NSURLFileSizeKey
                             error:&error];
    if (error != nil) {
        OWSLogDebug(@"Could not read data length from disk: %@, %@", self.fileUrl, error);
        OWSFailDebug(@"Could not read data length from disk with error: %@", error);
        return 0;
    }

    return fileSizeValue.unsignedIntegerValue;
}

- (nullable NSURL *)dataUrl
{
    OWSAssertDebug(!self.isConsumed);
    return self.fileUrl;
}

- (BOOL)isValidImage
{
    OWSAssertDebug(!self.isConsumed);
    return [NSData ows_isValidImageAtUrl:self.fileUrl mimeType:self.mimeType];
}

- (BOOL)isValidVideo
{
    OWSAssertDebug(!self.isConsumed);
    if (self.mimeType != nil) {
        if (![MIMETypeUtil isSupportedVideoMIMEType:self.mimeType]) {
            return NO;
        }
    } else if (![MIMETypeUtil isSupportedVideoFile:self.dataUrl.path]) {
        return NO;
    }
    return [OWSMediaUtils isValidVideoWithPath:self.dataUrl.path];
}

- (BOOL)hasStickerLikeProperties
{
    OWSAssertDebug(!self.isConsumed);
    return [NSData ows_hasStickerLikePropertiesWithPath:self.dataUrl.path];
}

- (ImageMetadata *)imageMetadata
{
    OWSAssertDebug(!self.isConsumed);

    @synchronized(self) {
        if (self.cachedImageMetadata != nil) {
            return self.cachedImageMetadata;
        }
        ImageMetadata *imageMetadata = [NSData imageMetadataWithPath:self.dataUrl.path
                                                            mimeType:self.mimeType
                                                      ignoreFileSize:YES];
        self.cachedImageMetadata = imageMetadata;
        return imageMetadata;
    }
}

- (BOOL)writeToUrl:(NSURL *)dstUrl error:(NSError **)outError
{
    OWSAssertDebug(!self.isConsumed);
    OWSAssertDebug(self.fileUrl);
    __block NSError *localError = nil;

    unsigned long long fileSize = self.dataLength;
    NSString *benchTitle = [NSString stringWithFormat:@"DataSourcePath copyItem with fileSize: %llu", fileSize];
    [BenchManager benchWithTitle:benchTitle
                           block:^{
                               BOOL success = [NSFileManager.defaultManager copyItemAtURL:self.fileUrl
                                                                                    toURL:dstUrl
                                                                                    error:&localError];
                               if (!success && !localError) {
                                   localError = OWSErrorMakeAssertionError(@"Could not write data source.");
                               }
                           }];

    if (localError != nil) {
        OWSLogDebug(@"Could not write data from: %@, to: %@, %@", self.fileUrl, dstUrl, localError);
        OWSFailDebug(@"Could not write data with error: %@", localError);
        if (outError != nil) {
            *outError = localError;
        }
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)moveToUrlAndConsume:(NSURL *)dstUrl error:(NSError **)outError
{
    OWSAssertDebug(!self.isConsumed);
    OWSAssertDebug(self.fileUrl);
    __block NSError *localError = nil;

    unsigned long long fileSize = self.dataLength;
    NSString *benchTitle = [NSString stringWithFormat:@"DataSourcePath moveItem with fileSize: %llu", fileSize];
    [BenchManager benchWithTitle:benchTitle
                           block:^{
                               self.isConsumed = YES;
                               BOOL success = NO;
                               if ([[NSFileManager defaultManager] isWritableFileAtPath:self.fileUrl.path]) {
                                   success = [OWSFileSystem moveFileFrom:self.fileUrl to:dstUrl error:&localError];
                               } else {
                                   OWSLogError(@"File was not writeable. Copying instead of moving.");
                                   success = [NSFileManager.defaultManager copyItemAtURL:self.fileUrl
                                                                                   toURL:dstUrl
                                                                                   error:&localError];
                               }
                               if (!success && !localError) {
                                   localError = OWSErrorMakeAssertionError(@"Could not move data source.");
                               }
                           }];

    if (localError != nil) {
        OWSLogDebug(@"Could not write data from: %@, to: %@, %@", self.fileUrl, dstUrl, localError);
        OWSFailDebug(@"Could not write data with error: %@", localError);
        if (outError != nil) {
            *outError = localError;
        }
        return NO;
    } else {
        return YES;
    }
}

- (nullable NSString *)mimeType
{
    OWSAssertDebug(!self.isConsumed);
    NSString *_Nullable fileExtension = self.fileUrl.pathExtension;
    return (fileExtension ? [MIMETypeUtil mimeTypeForFileExtension:fileExtension] : nil);
}

@end

NS_ASSUME_NONNULL_END
