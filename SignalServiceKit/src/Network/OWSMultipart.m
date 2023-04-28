//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSMultipart.h"

@interface OWSMultipartStreamDelegate : NSObject <NSStreamDelegate>

@property (atomic) BOOL hadError;

@end

#pragma mark -

@implementation OWSMultipartStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode == NSStreamEventErrorOccurred) {
        self.hadError = YES;
    }
}

@end

#pragma mark -

@implementation OWSMultipartTextPart

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value
{
    self = [super init];
    if (!self) {
        return self;
    }

    _key = key;
    _value = value;

    return self;
}

@end

#pragma mark -

// Copied verbatim from AFNetworking.

static NSString *AFCreateMultipartFormBoundary(void)
{
    return [NSString stringWithFormat:@"Boundary+%08X%08X", arc4random(), arc4random()];
}

static NSString *const kAFMultipartFormCRLF = @"\r\n";

static inline NSString *AFMultipartFormInitialBoundary(NSString *boundary)
{
    return [NSString stringWithFormat:@"--%@%@", boundary, kAFMultipartFormCRLF];
}

static inline NSString *AFMultipartFormEncapsulationBoundary(NSString *boundary)
{
    return [NSString stringWithFormat:@"%@--%@%@", kAFMultipartFormCRLF, boundary, kAFMultipartFormCRLF];
}

static inline NSString *AFMultipartFormFinalBoundary(NSString *boundary)
{
    return [NSString stringWithFormat:@"%@--%@--%@", kAFMultipartFormCRLF, boundary, kAFMultipartFormCRLF];
}

#pragma mark -

@implementation OWSMultipartBody

+ (BOOL)writeMultipartBodyForInputFileURL:(NSURL *)inputFileURL
                            outputFileURL:(NSURL *)outputFileURL
                                     name:(NSString *)name
                                 fileName:(NSString *)fileName
                                 mimeType:(NSString *)mimeType
                                 boundary:(NSString *)boundary
                                textParts:(NSArray<OWSMultipartTextPart *> *)textParts
                                    error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(inputFileURL);
    NSParameterAssert(outputFileURL);
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    if (![outputFileURL isFileURL]) {
        NSDictionary *userInfo = @{
            NSLocalizedFailureReasonErrorKey :
                NSLocalizedStringFromTable(@"Expected URL to be a file URL", @"AFNetworking", nil)
        };
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }

    // TODO: Audit streamStatus
    NSOutputStream *outputStream = [NSOutputStream outputStreamWithURL:outputFileURL append:NO];
    OWSMultipartStreamDelegate *outputStreamDelegate = [OWSMultipartStreamDelegate new];
    outputStream.delegate = outputStreamDelegate;
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream open];

    if (outputStream.streamStatus != NSStreamStatusOpen) {
        NSDictionary *userInfo = @{
            NSLocalizedFailureReasonErrorKey :
                NSLocalizedStringFromTable(@"File URL not reachable.", @"AFNetworking", nil)
        };
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }

    void (^closeOutputStream)(void) = ^{
        [outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream close];
    };

    BOOL isFirstPart = YES;
    for (OWSMultipartTextPart *textPart in textParts) {
        if (![self writeTextPartWithValue:textPart.value
                                     name:textPart.key
                                 boundary:boundary
                       hasInitialBoundary:isFirstPart
                         hasFinalBoundary:NO
                             outputStream:outputStream
                                    error:error]) {
            closeOutputStream();
            return NO;
        }
        isFirstPart = NO;
    }

    if (![self writeBodyPartWithInputFileURL:inputFileURL
                                        name:name
                                    fileName:fileName
                                    mimeType:mimeType
                                    boundary:boundary
                          hasInitialBoundary:isFirstPart
                            hasFinalBoundary:YES
                                outputStream:outputStream
                                       error:error]) {
        closeOutputStream();
        return NO;
    }

    closeOutputStream();

    if (outputStream.streamStatus != NSStreamStatusClosed || outputStreamDelegate.hadError) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        }
        return NO;
    }

    return YES;
}

+ (NSString *)createMultipartFormBoundary
{
    return AFCreateMultipartFormBoundary();
}

+ (BOOL)writeBodyPartWithInputFileURL:(NSURL *)inputFileURL
                                 name:(NSString *)name
                             fileName:(NSString *)fileName
                             mimeType:(NSString *)mimeType
                             boundary:(NSString *)boundary
                   hasInitialBoundary:(BOOL)hasInitialBoundary
                     hasFinalBoundary:(BOOL)hasFinalBoundary
                         outputStream:(NSOutputStream *)outputStream
                                error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(inputFileURL);
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);

    NSStringEncoding stringEncoding = NSUTF8StringEncoding;

    NSData *encapsulationBoundaryData =
        [(hasInitialBoundary ? AFMultipartFormInitialBoundary(boundary)
                             : AFMultipartFormEncapsulationBoundary(boundary)) dataUsingEncoding:stringEncoding];
    if (![self writeData:encapsulationBoundaryData outputStream:outputStream error:error]) {
        return NO;
    }

    NSDictionary *headers = [self headersForBodyWithName:name fileName:fileName mimeType:mimeType];
    NSString *headersString = [self stringForHeaders:headers];
    NSData *headersData = [headersString dataUsingEncoding:stringEncoding];
    if (![self writeData:headersData outputStream:outputStream error:error]) {
        return NO;
    }

    if (![self writeInputFileURL:inputFileURL outputStream:outputStream error:error]) {
        return NO;
    }

    NSData *closingBoundaryData
        = (hasFinalBoundary ? [AFMultipartFormFinalBoundary(boundary) dataUsingEncoding:stringEncoding]
                            : [NSData data]);
    if (![self writeData:closingBoundaryData outputStream:outputStream error:error]) {
        return NO;
    }

    return YES;
}

+ (BOOL)writeInputFileURL:(NSURL *)inputFileURL
             outputStream:(NSOutputStream *)outputStream
                    error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(inputFileURL);

    if (![inputFileURL isFileURL]) {
        NSDictionary *userInfo = @{
            NSLocalizedFailureReasonErrorKey :
                NSLocalizedStringFromTable(@"Expected URL to be a file URL", @"AFNetworking", nil)
        };
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    } else if ([inputFileURL checkResourceIsReachableAndReturnError:error] == NO) {
        NSDictionary *userInfo = @{
            NSLocalizedFailureReasonErrorKey :
                NSLocalizedStringFromTable(@"File URL not reachable.", @"AFNetworking", nil)
        };
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }

    NSDictionary *inputFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[inputFileURL path]
                                                                                         error:error];
    if (!inputFileAttributes) {
        return NO;
    }

    NSInputStream *inputStream = [NSInputStream inputStreamWithURL:inputFileURL];
    OWSMultipartStreamDelegate *inputStreamDelegate = [OWSMultipartStreamDelegate new];
    inputStream.delegate = inputStreamDelegate;
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [inputStream open];
    if (inputStream.streamStatus != NSStreamStatusOpen) {
        NSDictionary *userInfo = @{
            NSLocalizedFailureReasonErrorKey :
                NSLocalizedStringFromTable(@"File URL not reachable.", @"AFNetworking", nil)
        };
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }

    void (^closeInputStream)(void) = ^{
        [inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [inputStream close];
    };

    if (![self writeBodyInputStream:inputStream outputStream:outputStream error:error]) {
        closeInputStream();
        return NO;
    }

    closeInputStream();

    if (inputStream.streamStatus != NSStreamStatusClosed || inputStreamDelegate.hadError) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)writeTextPartWithValue:(NSString *)value
                          name:(NSString *)name
                      boundary:(NSString *)boundary
            hasInitialBoundary:(BOOL)hasInitialBoundary
              hasFinalBoundary:(BOOL)hasFinalBoundary
                  outputStream:(NSOutputStream *)outputStream
                         error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(value.length > 0);
    NSParameterAssert(name.length > 0);

    NSStringEncoding stringEncoding = NSUTF8StringEncoding;

    NSData *encapsulationBoundaryData =
        [(hasInitialBoundary ? AFMultipartFormInitialBoundary(boundary)
                             : AFMultipartFormEncapsulationBoundary(boundary)) dataUsingEncoding:stringEncoding];
    if (![self writeData:encapsulationBoundaryData outputStream:outputStream error:error]) {
        return NO;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary new];
    [headers setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"", name] forKey:@"Content-Disposition"];
    NSString *headersString = [self stringForHeaders:headers];
    NSData *headersData = [headersString dataUsingEncoding:stringEncoding];
    if (![self writeData:headersData outputStream:outputStream error:error]) {
        return NO;
    }

    NSData *valueData = [value dataUsingEncoding:stringEncoding];
    if (![self writeData:valueData outputStream:outputStream error:error]) {
        return NO;
    }

    NSData *closingBoundaryData
        = (hasFinalBoundary ? [AFMultipartFormFinalBoundary(boundary) dataUsingEncoding:stringEncoding]
                            : [NSData data]);
    if (![self writeData:closingBoundaryData outputStream:outputStream error:error]) {
        return NO;
    }

    return YES;
}

+ (BOOL)writeBodyInputStream:(NSInputStream *)inputStream
                outputStream:(NSOutputStream *)outputStream
                       error:(NSError *__autoreleasing *)error
{
    NSUInteger bufferSize = 16 * 1024;
    uint8_t buffer[bufferSize];

    NSInteger totalBytesReadCount = 0;
    while ([inputStream hasBytesAvailable]) {
        if (![outputStream hasSpaceAvailable]) {
            if (error) {
                *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            }
            return NO;
        }

        NSInteger numberOfBytesRead = [inputStream read:buffer maxLength:bufferSize];
        if (numberOfBytesRead < 0) {
            if (error) {
                *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            }
            return NO;
        }
        if (numberOfBytesRead == 0) {
            return YES;
        }
        totalBytesReadCount += numberOfBytesRead;

        NSUInteger numberOfBytesToWrite = (NSUInteger)numberOfBytesRead;

        NSUInteger totalBytesWrittenCount = 0;
        while (totalBytesWrittenCount < numberOfBytesToWrite) {
            NSUInteger writeSize = numberOfBytesToWrite - totalBytesWrittenCount;
            NSInteger bytesWrittenCount = [outputStream write:&buffer[totalBytesWrittenCount] maxLength:writeSize];
            if (bytesWrittenCount < 1) {
                *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
                return NO;
            }
            totalBytesWrittenCount += (NSUInteger)bytesWrittenCount;
        }
    }
    return YES;
}

+ (BOOL)writeData:(NSData *)data outputStream:(NSOutputStream *)outputStream error:(NSError *__autoreleasing *)error
{
    NSUInteger totalBytesCount = data.length;
    NSUInteger bufferSize = 16 * 1024;
    uint8_t buffer[bufferSize];

    NSUInteger totalBytesWrittenCount = 0;
    while (totalBytesWrittenCount < totalBytesCount) {
        NSUInteger blockSize = MIN((totalBytesCount - totalBytesWrittenCount), bufferSize);
        NSRange range = NSMakeRange((NSUInteger)totalBytesWrittenCount, blockSize);
        [data getBytes:buffer range:range];
        NSInteger bytesWrittenCount = [outputStream write:buffer maxLength:blockSize];
        if (bytesWrittenCount < 1) {
            *error = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            return NO;
        }
        totalBytesWrittenCount += (NSUInteger)bytesWrittenCount;
    }
    return YES;
}

+ (NSDictionary *)headersForBodyWithName:(NSString *)name fileName:(NSString *)fileName mimeType:(NSString *)mimeType
{
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName]
                      forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];
    return mutableHeaders;
}

+ (NSString *)stringForHeaders:(NSDictionary *)headers
{
    NSMutableString *headerString = [NSMutableString string];
    for (NSString *field in [headers allKeys]) {
        [headerString
            appendString:[NSString
                             stringWithFormat:@"%@: %@%@", field, [headers valueForKey:field], kAFMultipartFormCRLF]];
    }
    [headerString appendString:kAFMultipartFormCRLF];
    return [NSString stringWithString:headerString];
}

@end
