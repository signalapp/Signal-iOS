//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageFinder.h"
#import "OWSStorage.h"
#import "TSIncomingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSIncomingMessageFinderExtensionName = @"OWSIncomingMessageFinderExtensionName";

NSString *const OWSIncomingMessageFinderColumnTimestamp = @"OWSIncomingMessageFinderColumnTimestamp";
NSString *const OWSIncomingMessageFinderColumnPhoneNumber = @"OWSIncomingMessageFinderColumnPhoneNumber";
NSString *const OWSIncomingMessageFinderColumnUUID = @"OWSIncomingMessageFinderColumnUUID";
NSString *const OWSIncomingMessageFinderColumnSourceDeviceId = @"OWSIncomingMessageFinderColumnSourceDeviceId";

@implementation OWSIncomingMessageFinder

#pragma mark - init

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    return self;
}

#pragma mark - YAP integration

+ (YapDatabaseSecondaryIndex *)indexExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];

    [setup addColumn:OWSIncomingMessageFinderColumnTimestamp withType:YapDatabaseSecondaryIndexTypeInteger];
    [setup addColumn:OWSIncomingMessageFinderColumnPhoneNumber withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:OWSIncomingMessageFinderColumnUUID withType:YapDatabaseSecondaryIndexTypeText];
    [setup addColumn:OWSIncomingMessageFinderColumnSourceDeviceId withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexWithObjectBlock block = ^(YapDatabaseReadTransaction *transaction,
        NSMutableDictionary *dict,
        NSString *collection,
        NSString *key,
        id object) {
        if ([object isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)object;

            // On new messages authorId should be set on all incoming messages, but there was a time when authorId was
            // only set on incoming group messages.
            NSObject *phoneNumberOrNull = incomingMessage.authorAddress.phoneNumber ?: [NSNull null];
            NSObject *uuidStringOrNull = incomingMessage.authorAddress.uuidString ?: [NSNull null];
            [dict setObject:@(incomingMessage.timestamp) forKey:OWSIncomingMessageFinderColumnTimestamp];
            [dict setObject:phoneNumberOrNull forKey:OWSIncomingMessageFinderColumnPhoneNumber];
            [dict setObject:uuidStringOrNull forKey:OWSIncomingMessageFinderColumnUUID];
            [dict setObject:@(incomingMessage.sourceDeviceId) forKey:OWSIncomingMessageFinderColumnSourceDeviceId];
        }
    };

    YapDatabaseSecondaryIndexHandler *handler = [YapDatabaseSecondaryIndexHandler withObjectBlock:block];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:@"1"];
}

+ (NSString *)databaseExtensionName
{
    return OWSIncomingMessageFinderExtensionName;
}

+ (void)asyncRegisterExtensionWithPrimaryStorage:(OWSStorage *)storage
{
    OWSLogInfo(@"registering async.");
    [storage asyncRegisterExtension:self.indexExtension withName:OWSIncomingMessageFinderExtensionName];
}

#pragma mark - instance methods

- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                           address:(SignalServiceAddress *)address
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction
{
    NSUInteger count = 0;

    if (address.uuidString) {
        NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                          OWSIncomingMessageFinderColumnTimestamp,
                                          OWSIncomingMessageFinderColumnSourceDeviceId,
                                          OWSIncomingMessageFinderColumnUUID];

        // YapDatabaseQuery params must be objects
        YapDatabaseQuery *query =
            [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), @(sourceDeviceId), address.uuidString];

        BOOL success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count
                                                                                  matchingQuery:query];
        if (!success) {
            OWSFailDebug(@"Could not execute query");
            return NO;
        }
    }

    if (count == 0 && address.phoneNumber) {
        NSString *queryFormat = [NSString stringWithFormat:@"WHERE %@ = ? AND %@ = ? AND %@ = ?",
                                          OWSIncomingMessageFinderColumnTimestamp,
                                          OWSIncomingMessageFinderColumnSourceDeviceId,
                                          OWSIncomingMessageFinderColumnPhoneNumber];

        // YapDatabaseQuery params must be objects
        YapDatabaseQuery *query =
            [YapDatabaseQuery queryWithFormat:queryFormat, @(timestamp), @(sourceDeviceId), address.phoneNumber];

        BOOL success = [[transaction ext:OWSIncomingMessageFinderExtensionName] getNumberOfRows:&count
                                                                                  matchingQuery:query];
        if (!success) {
            OWSFailDebug(@"Could not execute query");
            return NO;
        }
    }

    return count > 0;
}

@end

NS_ASSUME_NONNULL_END
