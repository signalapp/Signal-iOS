//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/SPKProtocolContext.h>

NS_ASSUME_NONNULL_BEGIN

@class PreKeyRecord;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

@interface SSKPreKeyStore : NSObject

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

// MARK: AxolotlKit

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
                      protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext;

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
    protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext;

- (void)removePreKey:(int)preKeyId
     protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext;

@end

NS_ASSUME_NONNULL_END
