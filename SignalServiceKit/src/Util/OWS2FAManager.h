//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationName_2FAStateDidChange;

typedef void (^OWS2FASuccess)(void);
typedef void (^OWS2FAFailure)(NSError *error);

// This class can be safely accessed and used from any thread.
@interface OWS2FAManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (BOOL)is2FAEnabled;

- (void)enable2FAWithPin:(NSString *)pin
                 success:(nullable OWS2FASuccess)success
                 failure:(nullable OWS2FAFailure)failure;

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure;

@end

NS_ASSUME_NONNULL_END
