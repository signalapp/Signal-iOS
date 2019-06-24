//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class SignalAccount;
@class SignalServiceAddress;
@class YapDatabaseReadTransaction;

@interface SignalAccountFinder : NSObject

- (nullable SignalAccount *)signalAccountForAddress:(SignalServiceAddress *)address
                                    withTransaction:(YapDatabaseReadTransaction *)transaction;

+ (void)asyncRegisterDatabaseExtensions:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
