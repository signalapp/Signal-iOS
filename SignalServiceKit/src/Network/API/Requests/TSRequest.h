//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SMKUDAccessKey;

static NSString *const kSenderKeySendRequestBodyContentType = @"application/vnd.signal-messenger.mrm";

// TODO: Rework to _not_ extend NSMutableURLRequest.
@interface TSRequest : NSMutableURLRequest

@property (nonatomic) BOOL isUDRequest;
@property (nonatomic) BOOL shouldHaveAuthorizationHeaders;
@property (nonatomic) BOOL shouldRedactUrlInLogs;
@property (atomic, nullable) NSString *authUsername;
@property (atomic, nullable) NSString *authPassword;

/// If true, an HTTP 401 will mark the account as deregistered.
///
/// - Warning: This only applies to REST requests. We handle HTTP 403 errors
/// (*not* HTTP 401) for web sockets during the initial handshake, not
/// during the processing for individual requests.
@property (nonatomic) BOOL shouldMarkDeregisteredOn401;

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
