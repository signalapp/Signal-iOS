//
//  CCSMStorage.m
//  Forsta
//
//  Created by Greg Perkins on 5/27/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#import "CCSMStorage.h"
#import "Constraints.h"
#import "TSStorageHeaders.h"

#import <Foundation/Foundation.h>

@interface CCSMStorage()

@property (strong) YapDatabaseConnection *readConnection;
@property (strong) YapDatabaseConnection *writeConnection;

@end

@implementation CCSMStorage

@synthesize textSecureURL = _textSecureURL;
@synthesize readConnection = _readConnection;
@synthesize writeConnection = _writeConnection;


NSString *const CCSMStorageDatabaseCollection = @"CCSMInformation";

NSString *const CCSMStorageKeyOrgName = @"Organization Name";
NSString *const CCSMStorageKeyUserName = @"User Name";
NSString *const CCSMStorageKeySessionToken = @"Session Token";
NSString *const CCSMStorageKeyUserInfo = @"User Info";
NSString *const CCSMStorageKeyOrgInfo = @"Org Info";
NSString *const CCSMStorageKeyUsers = @"Users";
NSString *const CCSMStorageKeyTags = @"Tags";
NSString *const CCSMStorageKeyTSServerURL = @"TSServerURL";

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

-(instancetype)init
{
    if (self = [super init]) {
        _readConnection = [TSStorageManager.sharedManager newDatabaseConnection];
        _writeConnection =  [TSStorageManager.sharedManager newDatabaseConnection];
    }
    return self;
}

- (nullable id)tryGetValueForKey:(NSString *_Nonnull)key
{
//    return [TSStorageManager.sharedManager objectForKey:key inCollection:CCSMStorageDatabaseCollection];
    __block id returnVal = nil;
    [self.readConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        returnVal = [transaction objectForKey:key inCollection:CCSMStorageDatabaseCollection];
    }];
    return returnVal;
}

- (void)setValueForKey:(NSString *)key toValue:(nullable id)value
{
    ows_require(key != nil);
    
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:value forKey:key inCollection:CCSMStorageDatabaseCollection];
    }];
}


- (void)setUserName:(NSString *)value
{
    [self setValueForKey:CCSMStorageKeyUserName toValue:value];
}

- (nullable NSString *)getUserName
{
    return [self tryGetValueForKey:CCSMStorageKeyUserName];
}


- (void)setOrgName:(NSString *)value
{
    [self setValueForKey:CCSMStorageKeyOrgName toValue:value];
}

- (nullable NSString *)getOrgName
{
    return [self tryGetValueForKey:CCSMStorageKeyOrgName];
}


- (void)setSessionToken:(NSString *)value
{
    [self setValueForKey:CCSMStorageKeySessionToken toValue:value];
}

-(void)removeSessionToken
{
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction objectForKey:CCSMStorageKeySessionToken inCollection:CCSMStorageDatabaseCollection];
    }];
}

- (nullable NSString *)getSessionToken
{
    return [self tryGetValueForKey:CCSMStorageKeySessionToken];
}


- (void)setUserInfo:(NSDictionary *)value
{
    [self setValueForKey:CCSMStorageKeyUserInfo toValue:value];
}

- (nullable NSDictionary *)getUserInfo
{
    return [self tryGetValueForKey:CCSMStorageKeyUserInfo];
}


- (void)setOrgInfo:(NSDictionary *)value
{
    [self setValueForKey:CCSMStorageKeyOrgInfo toValue:value];
}

- (nullable NSDictionary *)getOrgInfo
{
    return [self tryGetValueForKey:CCSMStorageKeyOrgInfo];
}


- (void)setUsers:(NSMutableDictionary *)value
{
    [self setValueForKey:CCSMStorageKeyUsers toValue:value];
}

- (nullable NSMutableDictionary *)getUsers
{
    return [self tryGetValueForKey:CCSMStorageKeyUsers];
}


- (void)setTags:(NSDictionary *)value
{
    [self setValueForKey:CCSMStorageKeyTags toValue:value];
}

- (nullable NSDictionary *)getTags
{
    return [self tryGetValueForKey:CCSMStorageKeyTags];
}

-(NSString *)textSecureURL
{
    if (_textSecureURL == nil) {
        _textSecureURL = [self tryGetValueForKey:CCSMStorageKeyTSServerURL];
    }
    return _textSecureURL;
}

-(void)setTextSecureURL:(NSString *)value
{
    if (![_textSecureURL isEqualToString:value]) {
        _textSecureURL = [value copy];
        [self setValueForKey:CCSMStorageKeyTSServerURL toValue:value];
    }
}

-(NSDictionary *)extractTagsForUsers:(NSDictionary *) users
{
    NSMutableDictionary *tags = [NSMutableDictionary new];
    
    for (NSString *key in users.allKeys) {
        NSDictionary *userDict = [users objectForKey:key];
        NSDictionary *tagDict = [userDict objectForKey:@"tag"];
        NSString *slug = [tagDict objectForKey:@"slug"];
        if (slug) {
            [tags setObject:key forKey:slug];
        }
    }
    
    return [NSDictionary dictionaryWithDictionary:tags];
}

@end
