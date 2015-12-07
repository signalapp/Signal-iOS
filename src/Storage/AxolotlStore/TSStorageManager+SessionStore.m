//
//  TSStorageManager+SessionStore.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+SessionStore.h"

#define TSStorageManagerSessionStoreCollection @"TSStorageManagerSessionStoreCollection"

@implementation TSStorageManager (SessionStore)

- (SessionRecord *)loadSession:(NSString *)contactIdentifier deviceId:(int)deviceId {
    NSDictionary *dictionary =
        [self dictionaryForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    SessionRecord *record;

    if (dictionary) {
        record = [dictionary objectForKey:[self keyForInt:deviceId]];
    }

    if (!record) {
        return [SessionRecord new];
    }

    return record;
}

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier {
    NSDictionary *dictionary =
        [self objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    NSMutableArray *subDevicesSessions = [NSMutableArray array];

    if (dictionary) {
        for (NSString *key in [dictionary allKeys]) {
            NSNumber *number = @([key doubleValue]);

            [subDevicesSessions addObject:number];
        }
    }

    return subDevicesSessions;
}

- (void)storeSession:(NSString *)contactIdentifier deviceId:(int)deviceId session:(SessionRecord *)session {
    NSMutableDictionary *dictionary =
        [[self dictionaryForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection] mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary setObject:session forKey:[self keyForInt:deviceId]];

    [self setObject:dictionary forKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
}

- (BOOL)containsSession:(NSString *)contactIdentifier deviceId:(int)deviceId {
    return [self loadSession:contactIdentifier deviceId:deviceId].sessionState.hasSenderChain;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier deviceId:(int)deviceId {
    NSMutableDictionary *dictionary =
        [[self dictionaryForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection] mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary removeObjectForKey:[self keyForInt:deviceId]];

    [self setObject:dictionary forKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier {
    [self removeObjectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
}


- (NSNumber *)keyForInt:(int)number {
    return [NSNumber numberWithInt:number];
}

@end
