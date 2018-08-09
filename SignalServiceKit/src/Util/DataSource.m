//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DataSource.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "NSString+SSK.h"
#import "OWSFileSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataSource ()

@property (nonatomic) BOOL shouldDeleteOnDeallocation;

// The file path for the data, if it already exists on disk.
//
// This method is safe to call as it will not do any expensive reads or writes.
//
// May return nil if the data does not (yet) reside on disk.
//
// Use dataUrl instead if you need to access the data; it will
// ensure the data is on disk and return a URL, barring an error.
- (nullable NSString *)dataPathIfOnDisk;

@end

#pragma mark -

@implementation DataSource

- (NSData *)data
{
    OWSAbstractMethod();
    return nil;
}

- (nullable NSURL *)dataUrl
{
    OWSAbstractMethod();
    return nil;
}

- (nullable NSString *)dataPathIfOnDisk
{
    OWSAbstractMethod();
    return nil;
}

- (NSUInteger)dataLength
{
    OWSAbstractMethod();
    return 0;
}

- (BOOL)writeToPath:(NSString *)dstFilePath
{
    OWSAbstractMethod();
    return NO;
}

- (BOOL)isValidImage
{
    NSString *_Nullable dataPath = [self dataPathIfOnDisk];
    if (dataPath) {
        // if ows_isValidImage is given a file path, it will
        // avoid loading most of the data into memory, which
        // is considerably more performant, so try to do that.
        return [NSData ows_isValidImageAtPath:dataPath mimeType:self.mimeType];
    }
    NSData *data = [self data];
    return [data ows_isValidImage];
}

- (void)setSourceFilename:(nullable NSString *)sourceFilename
{
    _sourceFilename = sourceFilename.filterFilename;
}

// Returns the MIME type, if known.
- (nullable NSString *)mimeType
{
    OWSAbstractMethod();

    return nil;
}

@end

#pragma mark -

@interface DataSourceValue ()

@property (nonatomic) NSData *dataValue;

@property (nonatomic) NSString *fileExtension;

// This property is lazy-populated.
@property (nonatomic, nullable) NSString *cachedFilePath;

@end

#pragma mark -

@implementation DataSourceValue

- (void)dealloc
{
    if (self.shouldDeleteOnDeallocation) {
        NSString *_Nullable filePath = self.cachedFilePath;
        if (filePath) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error;
                BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
                if (!success || error) {
                    OWSCFail(@"DataSourceValue could not delete file: %@, %@", filePath, error);
                }
            });
        }
    }
}

+ (nullable DataSource *)dataSourceWithData:(NSData *)data
                              fileExtension:(NSString *)fileExtension
{
    OWSAssert(data);

    if (!data) {
        return nil;
    }

    DataSourceValue *instance = [DataSourceValue new];
    instance.dataValue = data;
    instance.fileExtension = fileExtension;
    instance.shouldDeleteOnDeallocation = YES;
    return instance;
}

+ (nullable DataSource *)dataSourceWithData:(NSData *)data
                                    utiType:(NSString *)utiType
{
    NSString *fileExtension = [MIMETypeUtil fileExtensionForUTIType:utiType];
    return [self dataSourceWithData:data fileExtension:fileExtension];
}

+ (nullable DataSource *)dataSourceWithOversizeText:(NSString *_Nullable)text
{
    if (!text) {
        return nil;
    }

    NSData *data = [text.filterStringForDisplay dataUsingEncoding:NSUTF8StringEncoding];
    return [self dataSourceWithData:data fileExtension:kOversizeTextAttachmentFileExtension];
}

+ (DataSource *)dataSourceWithSyncMessageData:(NSData *)data
{
    return [self dataSourceWithData:data fileExtension:kSyncMessageFileExtension];
}

+ (DataSource *)emptyDataSource
{
    return [self dataSourceWithData:[NSData new] fileExtension:@"bin"];
}

- (NSData *)data
{
    OWSAssert(self.dataValue);

    return self.dataValue;
}

- (nullable NSURL *)dataUrl
{
    NSString *_Nullable path = [self dataPath];
    return (path ? [NSURL fileURLWithPath:path] : nil);
}

- (nullable NSString *)dataPath
{
    OWSAssert(self.dataValue);

    @synchronized(self)
    {
        if (!self.cachedFilePath) {
            NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:self.fileExtension];
            if ([self writeToPath:filePath]) {
                self.cachedFilePath = filePath;
            } else {
                DDLogDebug(@"%@ Could not write data to disk: %@", self.logTag, self.fileExtension);
                OWSFail(@"%@ Could not write data to disk.", self.logTag);
            }
        }

        return self.cachedFilePath;
    }
}

- (nullable NSString *)dataPathIfOnDisk
{
    return self.cachedFilePath;
}

- (NSUInteger)dataLength
{
    OWSAssert(self.dataValue);

    return self.dataValue.length;
}

- (BOOL)writeToPath:(NSString *)dstFilePath
{
    OWSAssert(self.dataValue);

    // There's an odd bug wherein instances of NSData/Data created in Swift
    // code reliably crash on iOS 9 when calling [NSData writeToFile:...].
    // We can avoid these crashes by simply copying the Data.
    NSData *dataCopy = (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0) ? self.dataValue : [self.dataValue copy]);

    BOOL success = [dataCopy writeToFile:dstFilePath atomically:YES];
    if (!success) {
        DDLogDebug(@"%@ Could not write data to disk: %@", self.logTag, dstFilePath);
        OWSFail(@"%@ Could not write data to disk.", self.logTag);
        return NO;
    } else {
        return YES;
    }
}

- (nullable NSString *)mimeType
{
    return (self.fileExtension ? [MIMETypeUtil mimeTypeForFileExtension:self.fileExtension] : nil);
}

@end

#pragma mark -

@interface DataSourcePath ()

@property (nonatomic) NSString *filePath;

// These properties are lazy-populated.
@property (nonatomic) NSData *cachedData;
@property (nonatomic) NSNumber *cachedDataLength;

@end

#pragma mark -

@implementation DataSourcePath

- (void)dealloc
{
    if (self.shouldDeleteOnDeallocation) {
        NSString *filePath = self.filePath;
        if (filePath) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error;
                BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
                if (!success || error) {
                    OWSCFail(@"DataSourcePath could not delete file: %@, %@", filePath, error);
                }
            });
        }
    }
}

+ (nullable DataSource *)dataSourceWithURL:(NSURL *)fileUrl shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
{
    OWSAssert(fileUrl);

    if (!fileUrl || ![fileUrl isFileURL]) {
        return nil;
    }
    DataSourcePath *instance = [DataSourcePath new];
    instance.filePath = fileUrl.path;
    instance.shouldDeleteOnDeallocation = shouldDeleteOnDeallocation;
    return instance;
}

+ (nullable DataSource *)dataSourceWithFilePath:(NSString *)filePath
                     shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
{
    OWSAssert(filePath);

    if (!filePath) {
        return nil;
    }

    DataSourcePath *instance = [DataSourcePath new];
    instance.filePath = filePath;
    instance.shouldDeleteOnDeallocation = shouldDeleteOnDeallocation;
    return instance;
}

- (void)setFilePath:(NSString *)filePath
{
    OWSAssert(filePath.length > 0);

#ifdef DEBUG
    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
    OWSAssert(exists);
    OWSAssert(!isDirectory);
#endif

    _filePath = filePath;
}

- (NSData *)data
{
    OWSAssert(self.filePath);

    @synchronized(self)
    {
        if (!self.cachedData) {
            DDLogError(@"%@ ---- reading data", self.logTag);
            self.cachedData = [NSData dataWithContentsOfFile:self.filePath];
        }
        if (!self.cachedData) {
            DDLogDebug(@"%@ Could not read data from disk: %@", self.logTag, self.filePath);
            OWSFail(@"%@ Could not read data from disk.", self.logTag);
            self.cachedData = [NSData new];
        }
        return self.cachedData;
    }
}

- (nullable NSURL *)dataUrl
{
    OWSAssert(self.filePath);

    return [NSURL fileURLWithPath:self.filePath];
}

- (nullable NSString *)dataPath
{
    OWSAssert(self.filePath);

    return self.filePath;
}

- (nullable NSString *)dataPathIfOnDisk
{
    OWSAssert(self.filePath);

    return self.filePath;
}

- (NSUInteger)dataLength
{
    OWSAssert(self.filePath);

    @synchronized(self)
    {
        if (!self.cachedDataLength) {
            NSError *error;
            NSDictionary<NSFileAttributeKey, id> *_Nullable attributes =
                [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:&error];
            if (!attributes || error) {
                DDLogDebug(@"%@ Could not read data length from disk: %@, %@", self.logTag, self.filePath, error);
                OWSFail(@"%@ Could not read data length from disk with error: %@", self.logTag, error);
                self.cachedDataLength = @(0);
            } else {
                uint64_t fileSize = [attributes fileSize];
                self.cachedDataLength = @(fileSize);
            }
        }
        return [self.cachedDataLength unsignedIntegerValue];
    }
}

- (BOOL)writeToPath:(NSString *)dstFilePath
{
    OWSAssert(self.filePath);

    NSError *error;
    BOOL success = [[NSFileManager defaultManager] copyItemAtPath:self.filePath toPath:dstFilePath error:&error];
    if (!success || error) {
        DDLogDebug(
            @"%@ Could not write data from path: %@, to path: %@, %@", self.logTag, self.filePath, dstFilePath, error);
        OWSFail(@"%@ Could not write data with error: %@", self.logTag, error);
        return NO;
    } else {
        return YES;
    }
}

- (nullable NSString *)mimeType
{
    NSString *_Nullable fileExtension = self.filePath.pathExtension;
    return (fileExtension ? [MIMETypeUtil mimeTypeForFileExtension:fileExtension] : nil);
}

@end

NS_ASSUME_NONNULL_END
