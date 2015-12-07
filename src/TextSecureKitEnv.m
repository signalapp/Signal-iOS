//
//  TextSecureKitEnv.m
//  Pods
//
//  Created by Frederic Jacobs on 05/12/15.
//
//

#import "TextSecureKitEnv.h"

@implementation TextSecureKitEnv

+ (instancetype)sharedEnv {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
      sharedInstance = [self.class new];
    });
    return sharedInstance;
}

- (id<ContactsManagerProtocol>)contactsManager {
    NSAssert(_contactsManager, @"Trying to access the contactsManager before it's set.");

    return _contactsManager;
}

@end
