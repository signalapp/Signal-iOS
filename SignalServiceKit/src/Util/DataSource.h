//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// A protocol that abstracts away a source of NSData
// and allows us to:
//
// * Lazy-load if possible.
// * Avoid duplicate reads & writes.
@protocol DataSource

// Should not be called unless necessary as it can involve an expensive read.
- (NSData *)data;

// The URL for the data.  Should always be a File URL.
//
// Should not be called unless necessary as it can involve an expensive write.
//
// Will only return nil in the error case.
//
// TODO: Try to remove the parameter.
- (nullable NSURL *)dataUrl;

// The file path for the data.
//
// Should not be called unless necessary as it can involve an expensive write.
//
// Will only return nil in the error case.
//
// TODO: Try to remove the parameter.
- (nullable NSString *)dataPath;

// The file path for the data, if it already exists on disk.
//
// This method is safe to call as it will not do any expensive reads or writes.
//
// May return nil if the data does not reside on disk.
- (nullable NSString *)dataPathIfOnDisk;

// Will return zero in the error case.
- (NSUInteger)dataLength;

@end

#pragma mark -

@interface DataSourceValue : NSObject <DataSource>

+ (nullable id<DataSource>)dataSourceWithData:(NSData *)data fileExtension:(NSString *)fileExtension;

+ (nullable id<DataSource>)dataSourceWithData:(NSData *)data utiType:(NSString *)utiType;

+ (nullable id<DataSource>)dataSourceWithOversizeText:(NSString *_Nullable)text;

+ (id<DataSource>)emptyDataSource;

@end

#pragma mark -

@interface DataSourcePath : NSObject <DataSource>

+ (nullable id<DataSource>)dataSourceWithURL:(NSURL *)fileUrl;

+ (nullable id<DataSource>)dataSourceWithFilePath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
