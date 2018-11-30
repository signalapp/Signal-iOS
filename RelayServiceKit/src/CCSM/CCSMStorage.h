//
//  CCSMStorage.h
//  Forsta
//
//  Created by Greg Perkins on 5/27/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#ifndef CCSMStorage_h
#define CCSMStorage_h

extern NSString *const CCSMStorageDatabaseCollection;
extern NSString *const CCSMStorageKeyOrgName;
extern NSString *const CCSMStorageKeyUserName;
extern NSString *const CCSMStorageKeySessionToken;
extern NSString *const CCSMStorageKeyUserInfo;
extern NSString *const CCSMStorageKeyOrgInfo;
extern NSString *const CCSMStorageKeyUsers;
extern NSString *const CCSMStorageKeyTags;
extern NSString *const CCSMStorageKeyTSServerURL;


@interface CCSMStorage : NSObject

@property (strong) NSString *appGroupIdString;
@property (strong) NSString *textSecureURLString;
@property (strong) NSString *ccsmURLString;

+ (instancetype)sharedInstance;

- (NSString *)getOrgName;
- (void)setOrgName:(NSString *)value;

- (NSString *)getUserName;
- (void)setUserName:(NSString *)value;

- (NSString *)getSessionToken;
- (void)setSessionToken:(NSString *)value;
-(void)removeSessionToken;

- (NSDictionary *)getUserInfo;
- (void)setUserInfo:(NSDictionary *)value;

- (NSDictionary *)getOrgInfo;
- (void)setOrgInfo:(NSDictionary *)value;

- (NSDictionary *)getUsers;
- (void)setUsers:(NSDictionary *)value;

- (NSDictionary *)getTags;
-(void)setTags:(NSDictionary *)value;

@end

//@interface CCSMEnvironment : NSObject
//
//+ (instancetype)sharedInstance;
//
//@property NSString *appGroupIdString;
//@property NSString *ccsmURLString;
//
//@end

#endif /* Storage_h */

/*
 example:
    DDLogInfo(@"user name: %@", [Environment.ccsmStorage getUserName]);
    [Environment.ccsmStorage setUserName:@"gregperk"];
*/
