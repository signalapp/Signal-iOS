//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol KeychainStorage;

@interface TestKeychainStorage : NSObject <KeychainStorage>

@property (nonatomic) NSMutableDictionary<NSString *, NSData *> *dataMap;

@end

NS_ASSUME_NONNULL_END
