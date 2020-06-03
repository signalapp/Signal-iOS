//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSKeyValueStore;
@class SignalServiceAddress;

@interface CallKitIdStore : NSObject

+ (SDSKeyValueStore *)phoneNumberStore;
+ (SDSKeyValueStore *)uuidStore;

// phoneNumber is an e164 formatted phone number.
//
// callKitId is expected to have CallKitCallManager.kAnonymousCallHandlePrefix.
+ (void)setAddress:(SignalServiceAddress *)address forCallKitId:(NSString *)callKitId;

// returns an e164 formatted phone number or nil if no
// record can be found.
//
// callKitId is expected to have CallKitCallManager.kAnonymousCallHandlePrefix.
+ (SignalServiceAddress *)addressForCallKitId:(NSString *)callKitId;

@end

NS_ASSUME_NONNULL_END
