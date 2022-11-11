//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMultipartTextPart : NSObject

@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *value;

- (instancetype)initWithKey:(NSString *)key value:(NSString *)value;

@end

/// Based on AFNetworking's AFURLRequestSerialization.
@interface OWSMultipartBody : NSObject

+ (NSString *)createMultipartFormBoundary;

+ (BOOL)writeMultipartBodyForInputFileURL:(NSURL *)inputFileURL
                            outputFileURL:(NSURL *)outputFileURL
                                     name:(NSString *)name
                                 fileName:(NSString *)fileName
                                 mimeType:(NSString *)mimeType
                                 boundary:(NSString *)boundary
                                textParts:(NSArray<OWSMultipartTextPart *> *)textParts
                                    error:(NSError *__autoreleasing *)error;

@end

NS_ASSUME_NONNULL_END
