//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SMKUDAccessKey;

@interface TSRequest : NSMutableURLRequest

@property (nonatomic) BOOL isUDRequest;
@property (nonatomic) BOOL shouldHaveAuthorizationHeaders;
@property (atomic, nullable) NSString *authUsername;
@property (atomic, nullable) NSString *authPassword;
@property (atomic, nullable) NSString *customHost;
@property (atomic, nullable) NSString *customCensorshipCircumventionPrefix;

@property (nonatomic, readonly) NSDictionary<NSString *, id> *parameters;

+ (instancetype)new NS_UNAVAILABLE;
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

NS_ASSUME_NONNULL_END
