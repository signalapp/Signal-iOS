//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataSourceValue ()

@property (nonatomic) NSData *dataValue;

// This property is lazy-populated.
@property (nonatomic) NSString *cachedFilePath;

@end

#pragma mark -

@implementation DataSourceValue

+ (nullable id<DataSource>)dataSourceWithData:(NSData *)data
{
    OWSAssert(data);
    if (!data) {
        return nil;
    }

    DataSourceValue *instance = [DataSourceValue new];
    instance.dataValue = data;
    return instance;
}

+ (id<DataSource>)emptyDataSource
{
    return [self dataSourceWithData:[NSData new]];
}

- (NSData *)data
{
    OWSAssert(self.dataValue);

    return self.dataValue;
}

- (nullable NSURL *)dataUrl:(NSString *)fileExtension
{
    NSString *_Nullable path = [self dataPath:fileExtension];
    return (path ? [NSURL fileURLWithPath:path] : nil);
}

- (nullable NSString *)dataPath:(NSString *)fileExtension
{
    OWSAssert(self.dataValue);

    @synchronized(self)
    {
        if (!self.cachedFilePath) {
            NSString *dirPath = NSTemporaryDirectory();
            NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:fileExtension];
            NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
            if ([self.dataValue writeToFile:fileName atomically:YES]) {
                self.cachedFilePath = filePath;
            } else {
                OWSFail(@"%@ Could not write data to disk: %@", self.tag, fileExtension);
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

- (nullable NSURL *)dataUrl:(NSString *)fileExtension
{
    OWSAssert(self.filePath);

    return [NSURL fileURLWithPath:self.filePath];
}

- (nullable NSString *)dataPath:(NSString *)fileExtension
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

//#pragma mark -
//
//@interface DataSourceURL ()
//
//@property (nonatomic) NSURL *fileUrl;
//
//// These properties are lazy-populated.
//@property (nonatomic) NSData *cachedData;
//@property (nonatomic) NSNumber *cachedDataLength;
//
//@end
//
//#pragma mark -
//
//@implementation DataSourceURL
//
//+ (id<DataSource>)dataSourceWithURL:(NSURL *)fileUrl;
//{
//    DataSourceValue *instance = [DataSourceValue new];
//    instance.fileUrl = fileUrl;
//    return instance;
//}
//
//- (NSData *)data
//{
//    OWSAssert(self.filePath);
//
//    @synchronized (self) {
//        if (!self.cachedData) {
//            self.cachedData = [NSData dataWithContentsOfFile:self.filePath];
//        }
//        if (!self.cachedData) {
//            OWSFail(@"%@ Could not read data from disk: %@", self.tag, self.filePath);
//            self.cachedData = [NSData new];
//        }
//        return self.cachedData;
//    }
//}
//
//- (nullable NSURL *)dataUrl:(NSString *)fileExtension
//{
//    OWSAssert(self.filePath);
//
//    return [NSURL fileURLWithPath:self.filePath];
//}
//
//- (nullable NSString *)dataPath:(NSString *)fileExtension
//{
//    OWSAssert(self.filePath);
//
//    return self.filePath;
//}
//
//- (nullable NSString *)dataPathIfOnDisk
//{
//    OWSAssert(self.filePath);
//
//    return self.filePath;
//}
//
//- (NSUInteger)dataLength
//{
//    OWSAssert(self.filePath);
//
//    @synchronized (self) {
//        if (!self.cachedDataLength) {
//            NSError *error;
//            NSDictionary<NSFileAttributeKey, id> *_Nullable attributes =
//                [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:&error];
//            if (!attributes || error) {
//                OWSFail(@"%@ Could not read data length from disk: %@", self.tag, self.filePath);
//                self.cachedDataLength = @(0);
//            } else {
//                uint64_t fileSize = [attributes fileSize];
//                self.cachedDataLength = @(fileSize);
//            }
//        }
//        return [self.cachedDataLength unsignedIntegerValue];
//    }
//}
//
//#pragma mark - Logging
//
//+ (NSString *)tag
//{
//    return [NSString stringWithFormat:@"[%@]", self.class];
//}
//
//- (NSString *)tag
//{
//    return self.class.tag;
//}
//
//@end
//
//#pragma mark -
//
//
//@objc class DataSourcePath : NSObject, DataSource {
//    static let TAG = "[DataSourcePath]"
//
//        private let path : String
//
//                           private var cachedData : Data
//                                                    ?
//
//                                                    private var cachedLength
//                                                    : Int
//                                                    ?
//
//                                                    // MARK: Constructor
//
//                                                    internal required init(_ path
//                                                                           : String){ self.path = path super.init() }
//
//                                                    func
//                                                    data()
//                                                        ->Data
//    {
//        if
//            let cachedData
//                = cachedData{ return cachedData } Logger.error("\(DataSourcePath.TAG) reading data: \(path)") do
//            {
//                try
//                    cachedData = NSData(contentsOfFile : path) as Data
//            }
//        catch
//        {
//            owsFail("\(DataSourcePath.TAG) Could not read data from disk: \(path)") cachedData = Data()
//        }
//        return cachedData !
//    }
//
//        return cachedLength !
//    }
//}
//
//@objc class DataSourceUrl : NSObject,
//                            DataSource {
//    static let TAG = "[DataSourceUrl]"
//
//        private let url : URL
//
//                          private var cachedData : Data
//                                                   ?
//
//                                                   private var cachedLength
//                                                   : Int
//                                                   ?
//
//                                                   // MARK: Constructor
//
//                                                   internal required
//                                                   init(_ url
//                                                        : URL)
//    {
//        if
//            !url.isFileURL{ owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)") } self.url = url
//            super.init()
//    }
//
//    func data()->Data
//    {
//        if
//            let cachedData
//                = cachedData{ return cachedData } guard url
//                      .isFileURL else {
//                          owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)") return Data()
//                      } Logger.error("\(DataSourceUrl.TAG) reading data: \(url)") do
//            {
//                try
//                    cachedData = Data(contentsOf : url)
//            }
//        catch
//        {
//            owsFail("\(DataSourceUrl.TAG) Could not read data from disk: \(url)") cachedData = Data()
//        }
//        return cachedData !
//    }
//
//    func dataUrl(fileExtension
//                 : String)
//        ->URL
//        ? { return url }
//
//          func dataPath(fileExtension
//                        : String)
//              ->String
//        ? { guard url
//                  .isFileURL else {
//                      owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)") return nil } return url.path }
//
//          func dataPathIfOnDisk()
//              ->String
//        ? { guard url
//                  .isFileURL else {
//                      owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)") return nil } return url.path }
//
//          func dataLength()
//              ->Int
//    {
//        if
//            let cachedLength = cachedLength{ return cachedLength } guard url.isFileURL else
//            {
//                owsFail("\(DataSourceUrl.TAG) URL is not a file URL: \(url)") return 0
//            }
//
//        do {
//            let fileAttributes = try
//                FileManager.default.attributesOfItem(atPath
//                                                     : url.path) let fileSize
//                    = fileAttributes[FileAttributeKey.size] as !UInt64 cachedLength = Int(fileSize)
//        }
//        catch
//        {
//            owsFail("\(DataSourceUrl.TAG) Could not read data length from disk: \(url)") cachedLength = 0
//        }
//
//        return cachedLength !
//    }
//}

NS_ASSUME_NONNULL_END
