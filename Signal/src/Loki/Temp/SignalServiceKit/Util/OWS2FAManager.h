//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationName_2FAStateDidChange;

typedef void (^OWS2FASuccess)(void);
typedef void (^OWS2FAFailure)(NSError *error);

@class OWSPrimaryStorage;

// This class can be safely accessed and used from any thread.
@interface OWS2FAManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

@property (nullable, nonatomic, readonly) NSString *pinCode;

- (BOOL)is2FAEnabled;
- (BOOL)isDueForReminder;

// Request with service
- (void)requestEnable2FAWithPin:(NSString *)pin
                        success:(nullable OWS2FASuccess)success
                        failure:(nullable OWS2FAFailure)failure;

// Sore local settings if, used during registration
- (void)mark2FAAsEnabledWithPin:(NSString *)pin;

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure;

- (void)updateRepetitionIntervalWithWasSuccessful:(BOOL)wasSuccessful;

// used for testing
- (void)setDefaultRepetitionInterval;

@end

NS_ASSUME_NONNULL_END
