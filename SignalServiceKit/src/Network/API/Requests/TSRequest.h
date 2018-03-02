//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface TSRequest : NSMutableURLRequest

@property (nonatomic) BOOL shouldHaveAuthorizationHeaders;

@property (nonatomic) NSDictionary *parameters;

+ (instancetype)requestWithUrl:(NSURL *)url
                        method:(NSString *)method
                    parameters:(NSDictionary<NSString *, id> *)parameters;

@end
