//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIMessagesAssetLoader.h"
#import <SignalCoreKit/Randomness.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachment.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSImageDrawBlock)(CGContextRef context);

@implementation DebugUIMessagesAssetLoader

- (NSString *)labelEmoji
{
    return [TSAttachment emojiForMimeType:self.mimeType];
}

+ (DebugUIMessagesAssetLoader *)fakeAssetLoaderWithUrl:(NSString *)fileUrl mimeType:(NSString *)mimeType
{
    OWSAssertDebug(fileUrl.length > 0);
    OWSAssertDebug(mimeType.length > 0);

    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = mimeType;
    instance.filename = [NSURL URLWithString:fileUrl].lastPathComponent;
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureURLAssetLoaded:fileUrl success:success failure:failure];
    };
    return instance;
}

- (void)ensureURLAssetLoaded:(NSString *)fileUrl success:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    // Use a predictable file path so that we reuse the cache between app launches.
    NSString *temporaryDirectory = OWSTemporaryDirectory();
    NSString *cacheDirectory = [temporaryDirectory stringByAppendingPathComponent:@"cached_random_files"];
    [OWSFileSystem ensureDirectoryExists:cacheDirectory];
    NSString *filePath = [cacheDirectory stringByAppendingPathComponent:self.filename];
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath]) {
        self.filePath = filePath;
        return success();
    }

    OWSURLSession *urlSession =
        [[OWSURLSession alloc] initWithBaseUrl:nil
                                  frontingInfo:nil
                                securityPolicy:OWSURLSession.defaultSecurityPolicy
                                 configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                  extraHeaders:[NSDictionary new]
                             canUseSignalProxy:NO];
    [urlSession dataTask:fileUrl
        method:HTTPMethodGet
        headers:nil
        body:nil
        success:^(id<HTTPResponse> response) {
            NSData *_Nullable data = response.responseBodyData;
            if (data.length < 1) {
                OWSFailDebug(@"Error write url response [%@]: %@", fileUrl, filePath);
                failure();
                return;
            }
            if ([data writeToFile:filePath atomically:YES]) {
                self.filePath = filePath;
                OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);
                success();
            } else {
                OWSFailDebug(@"Error write url response [%@]: %@", fileUrl, filePath);
                failure();
            }
        }
        failure:^(NSError *error) {
            OWSFailDebug(@"Error downloading url[%@]: %@", fileUrl, error);
            failure();
        }];
}

#pragma mark -

+ (DebugUIMessagesAssetLoader *)fakePngAssetLoaderWithImageSize:(CGSize)imageSize
                                                backgroundColor:(UIColor *)backgroundColor
                                                      textColor:(UIColor *)textColor
                                                          label:(NSString *)label
{
    OWSAssertDebug(imageSize.width > 0);
    OWSAssertDebug(imageSize.height > 0);
    OWSAssertDebug(backgroundColor);
    OWSAssertDebug(textColor);
    OWSAssertDebug(label.length > 0);

    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = OWSMimeTypeImagePng;
    instance.filename = @"image.png";
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensurePngAssetLoaded:imageSize
                       backgroundColor:backgroundColor
                             textColor:textColor
                                 label:label
                               success:success
                               failure:failure];
    };
    return instance;
}

- (void)ensurePngAssetLoaded:(CGSize)imageSize
             backgroundColor:(UIColor *)backgroundColor
                   textColor:(UIColor *)textColor
                       label:(NSString *)label
                     success:(ActionSuccessBlock)success
                     failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);
    OWSAssertDebug(imageSize.width > 0 && imageSize.height > 0);
    OWSAssertDebug(backgroundColor);
    OWSAssertDebug(textColor);
    OWSAssertDebug(label.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    @autoreleasepool {
        NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"png"];
        UIImage *image = [self createRandomPngWithSize:imageSize
                                       backgroundColor:backgroundColor
                                             textColor:textColor
                                                 label:label];
        NSData *pngData = UIImagePNGRepresentation(image);
        [pngData writeToFile:filePath atomically:YES];
        self.filePath = filePath;
        OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);
        success();
    }
}

+ (DebugUIMessagesAssetLoader *)fakeNoisePngAssetLoaderWithSize:(NSUInteger)size
{
    OWSAssertDebug(size > 0);

    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = OWSMimeTypeImagePng;
    instance.filename = @"image.png";
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureNoisePngAssetLoaded:size success:success failure:failure];
    };
    return instance;
}

- (void)ensureNoisePngAssetLoaded:(NSUInteger)size
                          success:(ActionSuccessBlock)success
                          failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);
    OWSAssertDebug(size > 0);

    if (self.filePath) {
        success();
        return;
    }

    @autoreleasepool {
        NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"png"];
        UIImage *image = [self buildNoiseImageWithSize:size];
        NSData *pngData = UIImagePNGRepresentation(image);
        [pngData writeToFile:filePath atomically:YES];
        self.filePath = filePath;
        OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);
        success();
    }
}

- (nullable UIImage *)buildNoiseImageWithSize:(NSUInteger)size
{
    UIColor *backgroundColor = [UIColor colorWithRGBHex:0xaca6633];
    return [self imageWithSize:size
               backgroundColor:backgroundColor
                     drawBlock:^(CGContextRef context) {
                         const NSUInteger stride = 1;
                         for (NSUInteger x = 0; x < size; x += stride) {
                             for (NSUInteger y = 0; y < size; y += stride) {
                                 UIColor *color = [UIColor ows_randomColorWithIsAlphaRandom:NO];
                                 CGContextSetFillColorWithColor(context, color.CGColor);
                                 CGRect frame = CGRectMake(x, y, stride, stride);
                                 CGContextFillRect(context, frame);
                             }
                         }
                     }];
}

- (nullable UIImage *)imageWithSize:(NSUInteger)size
                    backgroundColor:(UIColor *)backgroundColor
                          drawBlock:(OWSImageDrawBlock)drawBlock
{
    OWSAssertDebug(drawBlock);
    OWSAssertDebug(backgroundColor);
    OWSAssertDebug(size > 0);

    CGRect frame = CGRectMake(0.0f, 0.0f, size, size);

    UIGraphicsBeginImageContextWithOptions(frame.size, NO, [UIScreen mainScreen].scale);
    CGContextRef _Nullable context = UIGraphicsGetCurrentContext();
    if (!context) {
        return nil;
    }

    CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
    CGContextFillRect(context, frame);

    CGContextSaveGState(context);
    drawBlock(context);
    CGContextRestoreGState(context);

    UIImage *_Nullable image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return image;
}

- (nullable UIImage *)createRandomPngWithSize:(CGSize)imageSize
                              backgroundColor:(UIColor *)backgroundColor
                                    textColor:(UIColor *)textColor
                                        label:(NSString *)label
{
    OWSAssertDebug(imageSize.width > 0 && imageSize.height > 0);
    OWSAssertDebug(backgroundColor);
    OWSAssertDebug(textColor);
    OWSAssertDebug(label.length > 0);

    @autoreleasepool {
        imageSize.width /= UIScreen.mainScreen.scale;
        imageSize.height /= UIScreen.mainScreen.scale;

        CGRect frame = CGRectZero;
        frame.size = imageSize;
        CGFloat smallDimension = MIN(imageSize.width, imageSize.height);
        UIFont *font = [UIFont boldSystemFontOfSize:smallDimension * 0.5f];
        NSDictionary *textAttributes = @{ NSFontAttributeName : font, NSForegroundColorAttributeName : textColor };

        CGRect textFrame =
            [label boundingRectWithSize:frame.size
                                options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                             attributes:textAttributes
                                context:nil];

        UIGraphicsBeginImageContextWithOptions(frame.size, NO, [UIScreen mainScreen].scale);
        CGContextRef context = UIGraphicsGetCurrentContext();

        CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
        CGContextFillRect(context, frame);
        [label drawAtPoint:CGPointMake(CGRectGetMidX(frame) - CGRectGetMidX(textFrame),
                               CGRectGetMidY(frame) - CGRectGetMidY(textFrame))
            withAttributes:textAttributes];

        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        return image;
    }
}

#pragma mark -

+ (DebugUIMessagesAssetLoader *)fakeRandomAssetLoaderWithLength:(NSUInteger)dataLength mimeType:(NSString *)mimeType
{
    OWSAssertDebug(dataLength > 0);
    OWSAssertDebug(mimeType.length > 0);

    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = mimeType;
    NSString *fileExtension = [MIMETypeUtil fileExtensionForMIMEType:mimeType];
    OWSAssertDebug(fileExtension.length > 0);
    instance.filename = [@"attachment" stringByAppendingPathExtension:fileExtension];
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureRandomAssetLoaded:dataLength success:success failure:failure];
    };
    return instance;
}

- (void)ensureRandomAssetLoaded:(NSUInteger)dataLength
                        success:(ActionSuccessBlock)success
                        failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(dataLength > 0);
    OWSAssertDebug(dataLength < INT_MAX);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    @autoreleasepool {
        NSString *fileExtension = [MIMETypeUtil fileExtensionForMIMEType:self.mimeType];
        OWSAssertDebug(fileExtension.length > 0);
        NSData *data = [Randomness generateRandomBytes:(int)dataLength];
        OWSAssertDebug(data);
        NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:fileExtension];
        BOOL didWrite = [data writeToFile:filePath atomically:YES];
        OWSAssertDebug(didWrite);
        self.filePath = filePath;
        OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);
    }

    success();
}

#pragma mark -

+ (DebugUIMessagesAssetLoader *)fakeMissingAssetLoaderWithMimeType:(NSString *)mimeType
{
    OWSAssertDebug(mimeType.length > 0);

    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = mimeType;
    NSString *fileExtension = [MIMETypeUtil fileExtensionForMIMEType:mimeType];
    OWSAssertDebug(fileExtension.length > 0);
    instance.filename = [@"attachment" stringByAppendingPathExtension:fileExtension];
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureMissingAssetLoaded:success failure:failure];
    };
    return instance;
}

- (void)ensureMissingAssetLoaded:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    NSString *fileExtension = [MIMETypeUtil fileExtensionForMIMEType:self.mimeType];
    OWSAssertDebug(fileExtension.length > 0);
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:fileExtension];
    BOOL didCreate = [NSFileManager.defaultManager createFileAtPath:filePath contents:nil attributes:nil];
    OWSAssertDebug(didCreate);
    self.filePath = filePath;
    OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);

    success();
}

#pragma mark -

+ (DebugUIMessagesAssetLoader *)fakeOversizeTextAssetLoader
{
    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = OWSMimeTypeOversizeTextMessage;
    instance.filename = @"attachment.txt";
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureOversizeTextAssetLoaded:success failure:failure];
    };
    return instance;
}

- (void)ensureOversizeTextAssetLoaded:(ActionSuccessBlock)success failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    NSMutableString *message = [NSMutableString new];
    for (NSUInteger i = 0; i < 32; i++) {
        [message appendString:@"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla "
                              @"vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel "
                              @"sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac "
                              @"sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper "
                              @"turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi "
                              @"semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum, "
                              @"vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet "
                              @"pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae "
                              @"dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis "
                              @"congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere "
                              @"lorem, in rhoncus nisi.\n\n"];
    }

    NSString *fileExtension = @"txt";
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:fileExtension];
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    OWSAssertDebug(data);
    BOOL didWrite = [data writeToFile:filePath atomically:YES];
    OWSAssertDebug(didWrite);
    self.filePath = filePath;
    OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);

    success();
}

#pragma mark -

+ (DebugUIMessagesAssetLoader *)fakeOversizeTextAssetLoaderWithText:(NSString *)text
{
    DebugUIMessagesAssetLoader *instance = [DebugUIMessagesAssetLoader new];
    instance.mimeType = OWSMimeTypeOversizeTextMessage;
    instance.filename = @"attachment.txt";
    __weak DebugUIMessagesAssetLoader *weakSelf = instance;
    instance.prepareBlock = ^(ActionSuccessBlock success, ActionFailureBlock failure) {
        [weakSelf ensureOversizeTextAssetLoadedWithText:text success:success failure:failure];
    };
    return instance;
}

- (void)ensureOversizeTextAssetLoadedWithText:(NSString *)text
                                      success:(ActionSuccessBlock)success
                                      failure:(ActionFailureBlock)failure
{
    OWSAssertDebug(success);
    OWSAssertDebug(failure);
    OWSAssertDebug(self.filename.length > 0);
    OWSAssertDebug(self.mimeType.length > 0);

    if (self.filePath) {
        success();
        return;
    }

    NSString *fileExtension = @"txt";
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:fileExtension];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    OWSAssertDebug(data);
    BOOL didWrite = [data writeToFile:filePath atomically:YES];
    OWSAssertDebug(didWrite);
    self.filePath = filePath;
    OWSAssertDebug([NSFileManager.defaultManager fileExistsAtPath:filePath]);

    success();
}

#pragma mark -

+ (instancetype)jpegInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader
            fakeAssetLoaderWithUrl:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-jpg.JPG"
                          mimeType:OWSMimeTypeImageJpeg];
    });
    return instance;
}

+ (instancetype)gifInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader
            fakeAssetLoaderWithUrl:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-gif.gif"
                          mimeType:OWSMimeTypeImageGif];
    });
    return instance;
}

+ (instancetype)largeGifInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance =
            [DebugUIMessagesAssetLoader fakeAssetLoaderWithUrl:@"https://i.giphy.com/media/LTw0F3GAdaao8/source.gif"
                                                      mimeType:OWSMimeTypeImageGif];
    });
    return instance;
}

+ (instancetype)mp3Instance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader
            fakeAssetLoaderWithUrl:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp3.mp3"
                          mimeType:@"audio/mp3"];
    });
    return instance;
}

+ (instancetype)mp4Instance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader
            fakeAssetLoaderWithUrl:@"https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp4.mp4"
                          mimeType:@"video/mp4"];
    });
    return instance;
}

+ (instancetype)compactPortraitPngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(60, 100)
                                                               backgroundColor:[UIColor blueColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"P"];
    });
    return instance;
}

+ (instancetype)compactLandscapePngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(100, 60)
                                                               backgroundColor:[UIColor greenColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"L"];
    });
    return instance;
}

+ (instancetype)tallPortraitPngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(10, 100)
                                                               backgroundColor:[UIColor yellowColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"P"];
    });
    return instance;
}

+ (instancetype)wideLandscapePngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(100, 10)
                                                               backgroundColor:[UIColor purpleColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"L"];
    });
    return instance;
}

+ (instancetype)largePngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(4000, 4000)
                                                               backgroundColor:[UIColor brownColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"B"];
    });
    return instance;
}

+ (instancetype)tinyPngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:CGSizeMake(2, 2)
                                                               backgroundColor:[UIColor cyanColor]
                                                                     textColor:[UIColor whiteColor]
                                                                         label:@"T"];
    });
    return instance;
}

+ (instancetype)pngInstanceWithSize:(CGSize)size
                    backgroundColor:(UIColor *)backgroundColor
                          textColor:(UIColor *)textColor
                              label:(NSString *)label
{
    return [DebugUIMessagesAssetLoader fakePngAssetLoaderWithImageSize:size
                                                       backgroundColor:backgroundColor
                                                             textColor:textColor
                                                                 label:label];
}

+ (instancetype)mediumFilesizePngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [DebugUIMessagesAssetLoader fakeNoisePngAssetLoaderWithSize:1000]; });
    return instance;
}

+ (instancetype)tinyPdfInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeRandomAssetLoaderWithLength:256 mimeType:@"application/pdf"];
    });
    return instance;
}

+ (instancetype)largePdfInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeRandomAssetLoaderWithLength:4 * 1024 * 1024
                                                                      mimeType:@"application/pdf"];
    });
    return instance;
}

+ (instancetype)missingPngInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeMissingAssetLoaderWithMimeType:OWSMimeTypeImagePng];
    });
    return instance;
}

+ (instancetype)missingPdfInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeMissingAssetLoaderWithMimeType:@"application/pdf"];
    });
    return instance;
}

+ (instancetype)oversizeTextInstance
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeOversizeTextAssetLoader];
    });
    return instance;
}

+ (instancetype)oversizeTextInstanceWithText:(NSString *)text
{
    static DebugUIMessagesAssetLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DebugUIMessagesAssetLoader fakeOversizeTextAssetLoaderWithText:text];
    });
    return instance;
}

#pragma mark -

+ (void)prepareAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
                    success:(dispatch_block_t)success
                    failure:(dispatch_block_t)failure
{

    NSMutableArray<AnyPromise *> *promises = [NSMutableArray array];
    NSMutableArray<NSError *> *errors = [NSMutableArray array];

    for (DebugUIMessagesAssetLoader *assetLoader in assetLoaders) {
        // Use chained promises to make the code more readable.
        AnyPromise *promise = AnyPromise.withFuture(^(AnyFuture *future) {
            assetLoader.prepareBlock(
                ^{
                    // The value doesn't matter, we just need any non-NSError value.
                    [future resolveWithValue:@1];
                },
                ^{
                    NSError *error =
                        [NSError errorWithDomain:@"DebugUI"
                                            code:0
                                        userInfo:@ { NSLocalizedDescriptionKey : @"Could not prepare fake assets." }];
                    @synchronized(errors) {
                        [errors addObject:error];
                    }
                    [future rejectWithError:error];
                });
        });
        [promises addObject:promise];
    }

    [AnyPromise whenResolved:promises].done(^(id value) { success(); }).catch(^(id error) {
        OWSLogError(@"Could not prepare fake asset loaders: %@.", error);
        failure();
    });
}

@end

NS_ASSUME_NONNULL_END

#endif
