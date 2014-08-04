//
//  UICKeyChainStore.h
//  UICKeyChainStore
//
//  Created by Kishikawa Katsumi on 11/11/20.
//  Copyright (c) 2011 Kishikawa Katsumi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UICKeyChainStore : NSObject

@property (nonatomic, readonly) NSString *service;
@property (nonatomic, readonly) NSString *accessGroup;

+ (NSString *)defaultService;
+ (void)setDefaultService:(NSString *)defaultService;

+ (UICKeyChainStore *)keyChainStore;
+ (UICKeyChainStore *)keyChainStoreWithService:(NSString *)service;
+ (UICKeyChainStore *)keyChainStoreWithService:(NSString *)service accessGroup:(NSString *)accessGroup;

- (instancetype)init;
- (instancetype)initWithService:(NSString *)service;
- (instancetype)initWithService:(NSString *)service accessGroup:(NSString *)accessGroup;

+ (NSString *)stringForKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key service:(NSString *)service;
+ (NSString *)stringForKey:(NSString *)key service:(NSString *)service accessGroup:(NSString *)accessGroup;
+ (BOOL)setString:(NSString *)value forKey:(NSString *)key;
+ (BOOL)setString:(NSString *)value forKey:(NSString *)key service:(NSString *)service;
+ (BOOL)setString:(NSString *)value forKey:(NSString *)key service:(NSString *)service accessGroup:(NSString *)accessGroup;

+ (NSData *)dataForKey:(NSString *)key;
+ (NSData *)dataForKey:(NSString *)key service:(NSString *)service;
+ (NSData *)dataForKey:(NSString *)key service:(NSString *)service accessGroup:(NSString *)accessGroup;
+ (BOOL)setData:(NSData *)data forKey:(NSString *)key;
+ (BOOL)setData:(NSData *)data forKey:(NSString *)key service:(NSString *)service;
+ (BOOL)setData:(NSData *)data forKey:(NSString *)key service:(NSString *)service accessGroup:(NSString *)accessGroup;

- (void)setString:(NSString *)string forKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;

- (void)setData:(NSData *)data forKey:(NSString *)key;
- (NSData *)dataForKey:(NSString *)key;

+ (BOOL)removeItemForKey:(NSString *)key;
+ (BOOL)removeItemForKey:(NSString *)key service:(NSString *)service;
+ (BOOL)removeItemForKey:(NSString *)key service:(NSString *)service accessGroup:(NSString *)accessGroup;
+ (BOOL)removeAllItems;
+ (BOOL)removeAllItemsForService:(NSString *)service;
+ (BOOL)removeAllItemsForService:(NSString *)service accessGroup:(NSString *)accessGroup;

- (void)removeItemForKey:(NSString *)key;
- (void)removeAllItems;

- (void)synchronize;

// object subscripting

- (NSString *)objectForKeyedSubscript:(NSString <NSCopying> *)key;
- (void)setObject:(NSString *)obj forKeyedSubscript:(NSString <NSCopying> *)key;

@end
