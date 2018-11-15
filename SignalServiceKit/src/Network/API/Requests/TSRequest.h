//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class SMKUDAccessKey;

@interface TSRequest : NSMutableURLRequest

@property (nonatomic) BOOL isUDRequest;
@property (nonatomic) BOOL shouldHaveAuthorizationHeaders;
@property (atomic, nullable) NSString *authUsername;
@property (atomic, nullable) NSString *authPassword;

@property (nonatomic, readonly) NSDictionary<NSString *, id> *parameters;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithURL:(NSURL *)URL;

- (instancetype)initWithURL:(NSURL *)URL
                cachePolicy:(NSURLRequestCachePolicy)cachePolicy
            timeoutInterval:(NSTimeInterval)timeoutInterval NS_UNAVAILABLE;

- (instancetype)initWithURL:(NSURL *)URL
                     method:(NSString *)method
                 parameters:(nullable NSDictionary<NSString *, id> *)parameters;

+ (instancetype)requestWithUrl:(NSURL *)url
                        method:(NSString *)method
                    parameters:(nullable NSDictionary<NSString *, id> *)parameters;

@end
