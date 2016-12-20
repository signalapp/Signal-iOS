// Created by Michael Kirk on 12/20/16.
// Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSAccountManager;
@class AFHTTPSessionManager;

@interface OWSSignalService : NSObject

@property (nonatomic, readonly) BOOL isCensored;
@property (nonatomic, readonly) AFHTTPSessionManager *HTTPSessionManager;

@end

NS_ASSUME_NONNULL_END
