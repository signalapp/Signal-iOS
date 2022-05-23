#import "DataSource.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSFileSystem.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit-Swift.h>

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
    return nil;
}

- (nullable NSURL *)dataUrl
{
    return nil;
}

- (nullable NSString *)dataPathIfOnDisk
{
    return nil;
}

- (NSUInteger)dataLength
{
    return 0;
}

- (BOOL)writeToPath:(NSString *)dstFilePath
{
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

- (BOOL)isValidVideo
{
    return [OWSMediaUtils isValidVideoWithPath:self.dataUrl.path];
}

- (void)setSourceFilename:(nullable NSString *)sourceFilename
{
    _sourceFilename = sourceFilename.filterFilename;
}

// Returns the MIME type, if known.
- (nullable NSString *)mimeType
{
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
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
            });
        }
    }
}

+ (nullable DataSource *)dataSourceWithData:(NSData *)data
                              fileExtension:(NSString *)fileExtension
{
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

+ (nullable DataSource *)dataSourceWithText:(NSString *_Nullable)text
{
    if (!text) {
        return nil;
    }

    NSData *data = [text.filterStringForDisplay dataUsingEncoding:NSUTF8StringEncoding];
    return [self dataSourceWithData:data fileExtension:kTextAttachmentFileExtension];
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
    return self.dataValue;
}

- (nullable NSURL *)dataUrl
{
    NSString *_Nullable path = [self dataPath];
    return (path ? [NSURL fileURLWithPath:path] : nil);
}

- (nullable NSString *)dataPath
{
    @synchronized(self)
    {
        if (!self.cachedFilePath) {
            NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:self.fileExtension];
            if ([self writeToPath:filePath]) {
                self.cachedFilePath = filePath;
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
    return self.dataValue.length;
}

- (BOOL)writeToPath:(NSString *)dstFilePath
{
    NSData *dataCopy = self.dataValue;

    BOOL success = [dataCopy writeToFile:dstFilePath atomically:YES];
    if (!success) {
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
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
            });
        }
    }
}

+ (nullable DataSource *)dataSourceWithURL:(NSURL *)fileUrl shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation
{
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
    _filePath = filePath;
}

- (NSData *)data
{
    @synchronized(self)
    {
        if (!self.cachedData) {
            self.cachedData = [NSData dataWithContentsOfFile:self.filePath];
        }
        if (!self.cachedData) {
            self.cachedData = [NSData new];
        }
        return self.cachedData;
    }
}

- (nullable NSURL *)dataUrl
{
    return [NSURL fileURLWithPath:self.filePath];
}

- (nullable NSString *)dataPath
{
    return self.filePath;
}

- (nullable NSString *)dataPathIfOnDisk
{
    return self.filePath;
}

- (NSUInteger)dataLength
{
    @synchronized(self)
    {
        if (!self.cachedDataLength) {
            NSError *error;
            NSDictionary<NSFileAttributeKey, id> *_Nullable attributes =
                [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:&error];
            if (!attributes || error) {
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
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] copyItemAtPath:self.filePath toPath:dstFilePath error:&error];
    if (!success || error) {
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
