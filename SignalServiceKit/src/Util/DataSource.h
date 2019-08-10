//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// A base class that abstracts away a source of NSData
// and allows us to:
//
// * Lazy-load if possible.
// * Avoid duplicate reads & writes.
@protocol DataSource <NSObject>

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

@interface DataSourceValue : NSObject <DataSource>

+ (_Nullable id<DataSource>)dataSourceWithData:(NSData *)data fileExtension:(NSString *)fileExtension;

+ (_Nullable id<DataSource>)dataSourceWithData:(NSData *)data utiType:(NSString *)utiType;

+ (_Nullable id<DataSource>)dataSourceWithOversizeText:(NSString *_Nullable)text;

+ (id<DataSource>)dataSourceWithSyncMessageData:(NSData *)data;

+ (id<DataSource>)emptyDataSource;

@end

#pragma mark -

@interface DataSourcePath : NSObject <DataSource>

+ (_Nullable id<DataSource>)dataSourceWithURL:(NSURL *)fileUrl shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation;

+ (_Nullable id<DataSource>)dataSourceWithFilePath:(NSString *)filePath
                     shouldDeleteOnDeallocation:(BOOL)shouldDeleteOnDeallocation;

@end

NS_ASSUME_NONNULL_END
