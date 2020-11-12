#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSRequest

- (id)initWithURL:(NSURL *)URL {
    self = [super initWithURL:URL
                  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
              timeoutInterval:textSecureHTTPTimeOut];

    if (!self) {
        return nil;
    }

    _parameters = @{};

    return self;
}

- (instancetype)init
{
    return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (instancetype)initWithURL:(NSURL *)URL
                cachePolicy:(NSURLRequestCachePolicy)cachePolicy
            timeoutInterval:(NSTimeInterval)timeoutInterval
{
    return nil;
}

- (instancetype)initWithURL:(NSURL *)URL
                     method:(NSString *)method
                 parameters:(nullable NSDictionary<NSString *, id> *)parameters
{
    self = [super initWithURL:URL
                  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
              timeoutInterval:textSecureHTTPTimeOut];

    if (!self) {
        return nil;
    }

    _parameters = parameters ?: @{};

    [self setHTTPMethod:method];

    return self;
}

+ (instancetype)requestWithUrl:(NSURL *)url
                        method:(NSString *)method
                    parameters:(nullable NSDictionary<NSString *, id> *)parameters
{
    return [[TSRequest alloc] initWithURL:url method:method parameters:parameters];
}

@end

NS_ASSUME_NONNULL_END
