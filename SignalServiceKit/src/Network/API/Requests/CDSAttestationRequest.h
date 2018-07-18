//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface CDSAttestationRequest : TSRequest

@property (nonatomic, readonly) NSString *authToken;

- (instancetype)init NS_UNAVAILABLE;

- (TSRequest *)initWithURL:(NSURL *)URL
                    method:(NSString *)method
                parameters:(nullable NSDictionary<NSString *, id> *)parameters
                 authToken:(NSString *)authToken;

@end

NS_ASSUME_NONNULL_END
