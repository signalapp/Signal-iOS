//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const NSNotificationName_2FAStateDidChange;

extern const NSUInteger kMin2FAPinLength;
extern const NSUInteger kMin2FAv2PinLength;
extern const NSUInteger kMax2FAv1PinLength;
extern const NSUInteger kLegacyTruncated2FAv1PinLength;

typedef void (^OWS2FASuccess)(void);
typedef void (^OWS2FAFailure)(NSError *error);

typedef NS_ENUM(NSUInteger, OWS2FAMode) {
    OWS2FAMode_Disabled = 0,
    OWS2FAMode_V1,
    OWS2FAMode_V2,
};

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

// This class can be safely accessed and used from any thread.
@interface OWS2FAManager : NSObject

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

@property (nullable, nonatomic, readonly) NSString *pinCode;
@property (nonatomic, readonly) OWS2FAMode mode;
@property (nonatomic, readonly) BOOL isDueForV1Reminder;
@property (nonatomic, readonly) NSTimeInterval repetitionInterval;

- (BOOL)is2FAEnabled;
- (BOOL)needsLegacyPinMigration;
- (void)verifyPin:(NSString *)pin result:(void (^_Nonnull)(BOOL))result;

- (BOOL)isDueForV2ReminderWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(isDueForV2Reminder(transaction:));

// Request with service
- (void)requestEnable2FAWithPin:(NSString *)pin
                           mode:(OWS2FAMode)mode
                        success:(nullable OWS2FASuccess)success
                        failure:(nullable OWS2FAFailure)failure;

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure;

- (void)updateRepetitionIntervalWithWasSuccessful:(BOOL)wasSuccessful;

- (void)mark2FAAsEnabledWithPin:(NSString *)pin;

// used for testing
- (void)setDefaultRepetitionIntervalWithTransaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
