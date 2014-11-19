//
//  TSYapDatabaseObject.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"
#import "TSStorageManager.h"

@implementation TSYapDatabaseObject

- (id)init{
    if (self = [super init])
    {
        _uniqueId = [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId{
    if (self = [super init]) {
        _uniqueId = uniqueId;
    }
    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction{
    [transaction setObject:self forKey:self.uniqueId inCollection:[[self class] collection]];
}

- (void)save{
    [[TSStorageManager sharedManager].databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self saveWithTransaction:transaction];
    }];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction removeObjectForKey:self.uniqueId inCollection:[[self class] collection]];
}


- (void)remove{
    [[TSStorageManager sharedManager].databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self removeWithTransaction:transaction];
    }];
}


#pragma - mark Class Methods

+ (NSString *)collection{
    return NSStringFromClass([self class]);
}

+ (instancetype) fetchObjectWithUniqueID:(NSString *)uniqueID transaction:(YapDatabaseReadTransaction *)transaction {
    return [transaction objectForKey:uniqueID inCollection:[self collection]];
}

+ (instancetype) fetchObjectWithUniqueID:(NSString *)uniqueID{
    __block id object;
    
    [[TSStorageManager sharedManager].databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:uniqueID inCollection:[self collection]];
    }];
    
    return object;
}

@end
