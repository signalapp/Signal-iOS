//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// A base class that abstracts away a source of NSData
// and allows us to:
//
// * Lazy-load if possible.
// * Avoid duplicate reads & writes.
@interface DataSource : NSObject

@property (nonatomic, nullable) NSString *sourceFilename;

// Should not be called unless necessary as it can involve an expensive read.
- (NSData *)data;

// The URL for the data.  Should always be a File URL.
//
// Should not be called unless necessary as it can involve an expensive write.
//
// Will only return nil in the error case.
- (nullable NSURL *)dataUrl;

// Will return zero in the error case.
- (NSUInteger)dataLength;

// Returns YES on success.
- (BOOL)writeToPath:(NSString *)dstFilePath;

- (BOOL)isValidImage;

- (BOOL)isValidVideo;

@end

#pragma mark -

@interface DataSourceValue : DataSource

+ (nullable DataSource *)dataSourceWithData:(NSData *)data fileExtension:(NSString *)fileExtension;

+ (nullable DataSource *)dataSourceWithData:(NSData *)data utiType:(NSString *)utiType;

+ (nullable DataSource *)dataSourceWithOversizeText:(NSString *_Nullable)text;

+ (DataSource *)dataSourceWithSyncMessageData:(NSData *)data;

+ (DataSource *)emptyDataSource;

@end

#pragma mark -

@interface DataSourcePath : DataSource

+ (nullable DataSource *)dataSourceWithURL:(NSURL *)fileUrl shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation;

+ (nullable DataSource *)dataSourceWithFilePath:(NSString *)filePath
                     shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation;

@end

NS_ASSUME_NONNULL_END
