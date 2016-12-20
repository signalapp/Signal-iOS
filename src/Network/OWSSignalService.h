// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class AFHTTPSessionManager;

@interface OWSSignalService : NSObject

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager;

@property (nonatomic, readonly) BOOL isCensored;
@property (nonatomic, readonly) AFHTTPSessionManager *HTTPSessionManager;

@end

NS_ASSUME_NONNULL_END
