//
//  FLTag.m
//  Forsta
//
//  Created by Mark on 9/29/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#import "FLTag.h"
#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import <RelayServiceKit/RelayServiceKit-Swift.h>

#define FLTagDescriptionKey @"description"
#define FLTagIdKey @"id"
#define FLTagURLKey @"url"
#define FLTagSlugKey @"slug"
#define FLTagOrgKey @"org"
#define FLTagUsersKey @"users"

@interface FLTag()

@property (nonatomic, strong) NSDictionary *tagDictionary;

@end

@implementation FLTag

+(instancetype _Nullable)getOrCreateTagWithDictionary:(NSDictionary *_Nonnull)tagDictionary;
{
    __block FLTag *aTag = nil;
    [[OWSPrimaryStorage sharedManager].dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        aTag = [self getOrCreateTagWithDictionary:tagDictionary transaction:transaction];
    }];
    return aTag;
}

+(instancetype _Nullable)getOrCreateTagWithDictionary:(NSDictionary *_Nonnull)tagDictionary transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction;
{
    if (![tagDictionary respondsToSelector:@selector(objectForKey:)]) {
        DDLogDebug(@"Attempted to update FLTag with bad object: %@", tagDictionary);
        return nil;
    }
    
    NSString *tagId = [tagDictionary objectForKey:FLTagIdKey];
    FLTag *aTag = [self getOrCreateTagWithId:tagId transaction:transaction];
    
    if ([tagDictionary objectForKey:FLTagURLKey])
        aTag.url = [tagDictionary objectForKey:FLTagURLKey];
    
    if ([tagDictionary objectForKey:FLTagDescriptionKey])
        aTag.tagDescription = [tagDictionary objectForKey:FLTagDescriptionKey];
    
    if ([tagDictionary objectForKey:FLTagSlugKey])
        aTag.slug = [tagDictionary objectForKey:FLTagSlugKey];
    
    NSArray *users = [tagDictionary objectForKey:FLTagUsersKey];
    NSMutableArray *holdingArray = [NSMutableArray new];
    id object = [tagDictionary objectForKey:@"user"];
    if (![[object class] isEqual:[NSNull class]]) {
        NSDictionary *singleUser = (NSDictionary *)object;
        NSString *uid = [singleUser objectForKey:FLTagIdKey];
        if (uid) {
            [holdingArray addObject:uid];
        }
    }
    [users enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id associationType = [obj objectForKey:@"association_type"];
        if (![[associationType class] isEqual:[NSNull class]]) {
            if ([associationType isEqualToString:@"MEMBEROF"]) {
                NSDictionary *user = [obj objectForKey:@"user"];
                if (user) {
                    [holdingArray addObject:[user objectForKey:FLTagIdKey]];
                }
            }
        }
    }];
    aTag.recipientIds = [NSCountedSet setWithArray:holdingArray];
    
    NSDictionary *orgDict = [tagDictionary objectForKey:FLTagOrgKey];
    if (orgDict) {
        aTag.orgSlug = [orgDict objectForKey:FLTagSlugKey];
        aTag.orgUrl = [orgDict objectForKey:FLTagURLKey];
    }
    
    [aTag saveWithTransaction:transaction];
    
    return aTag;
}

+(instancetype _Nonnull)getOrCreateTagWithId:(NSString *_Nonnull)tagId
{
    __block FLTag *aTag = nil;
    [[OWSPrimaryStorage sharedManager].dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [self getOrCreateTagWithId:tagId transaction:transaction];
    }];
    return aTag;
}

+(instancetype _Nonnull)getOrCreateTagWithId:(NSString *_Nonnull)tagId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    FLTag *aTag = [self fetchObjectWithUniqueID:tagId transaction:transaction];
    if (!aTag) {
        aTag = [[FLTag alloc] initWithUniqueId:tagId];
    }
    
    return aTag;
}


-(NSString *)displaySlug
{
    NSString *slugDisplayString = [NSString stringWithFormat:@"@%@", self.slug];
    if (![TSAccountManager.sharedInstance.selfRecipient.flTag.orgSlug isEqualToString:self.orgSlug]) {
        slugDisplayString = [slugDisplayString stringByAppendingString:[NSString stringWithFormat:@":%@", self.orgSlug]];
    }
    return slugDisplayString;
}

-(UIImage *)avatar
{
    _avatar = nil;
    return _avatar;
}

+ (NSString *)collection
{
    return NSStringFromClass([self class]);
}

@end
