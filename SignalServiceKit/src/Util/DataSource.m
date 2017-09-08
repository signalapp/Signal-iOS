//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DataSource.h"
#import "MIMETypeUtil.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataSourceValue ()

@property (nonatomic) NSData *dataValue;

@property (nonatomic) NSString *fileExtension;

// This property is lazy-populated.
@property (nonatomic) NSString *cachedFilePath;

@end

#pragma mark -

@implementation DataSourceValue

+ (nullable id<DataSource>)dataSourceWithData:(NSData *)data fileExtension:(NSString *)fileExtension
{
    OWSAssert(data);

    if (!data) {
        return nil;
    }

    DataSourceValue *instance = [DataSourceValue new];
    instance.dataValue = data;
    instance.fileExtension = fileExtension;
    return instance;
}

+ (nullable id<DataSource>)dataSourceWithData:(NSData *)data utiType:(NSString *)utiType
{
    NSString *fileExtension = [MIMETypeUtil fileExtensionForUTIType:utiType];
    return [self dataSourceWithData:data fileExtension:fileExtension];
}

+ (nullable id<DataSource>)dataSourceWithOversizeText:(NSString *_Nullable)text
{
    OWSAssert(text);

    if (!text) {
        return nil;
    }

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [self dataSourceWithData:data fileExtension:kOversizeTextAttachmentFileExtension];
}

+ (id<DataSource>)emptyDataSource
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
            NSString *dirPath = NSTemporaryDirectory();
            NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:self.fileExtension];
            NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
            if ([self.dataValue writeToFile:fileName atomically:YES]) {
                self.cachedFilePath = filePath;
            } else {
                OWSFail(@"%@ Could not write data to disk: %@", self.tag, self.fileExtension);
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

#pragma mark -

@interface DataSourcePath ()

@property (nonatomic) NSString *filePath;

// These properties are lazy-populated.
@property (nonatomic) NSData *cachedData;
@property (nonatomic) NSNumber *cachedDataLength;

@end

#pragma mark -

@implementation DataSourcePath

+ (nullable id<DataSource>)dataSourceWithURL:(NSURL *)fileUrl;
{
    OWSAssert(fileUrl);

    if (!fileUrl || ![fileUrl isFileURL]) {
        return nil;
    }
    DataSourcePath *instance = [DataSourcePath new];
    instance.filePath = fileUrl.path;
    return instance;
}

+ (nullable id<DataSource>)dataSourceWithFilePath:(NSString *)filePath;
{
    OWSAssert(filePath);

    if (!filePath) {
        return nil;
    }

    DataSourcePath *instance = [DataSourcePath new];
    instance.filePath = filePath;
    return instance;
}

- (NSData *)data
{
    OWSAssert(self.filePath);

    @synchronized(self)
    {
        if (!self.cachedData) {
            self.cachedData = [NSData dataWithContentsOfFile:self.filePath];
        }
        if (!self.cachedData) {
            OWSFail(@"%@ Could not read data from disk: %@", self.tag, self.filePath);
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
                OWSFail(@"%@ Could not read data length from disk: %@", self.tag, self.filePath);
                self.cachedDataLength = @(0);
            } else {
                uint64_t fileSize = [attributes fileSize];
                self.cachedDataLength = @(fileSize);
            }
        }
        return [self.cachedDataLength unsignedIntegerValue];
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
