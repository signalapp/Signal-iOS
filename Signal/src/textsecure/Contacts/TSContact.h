//
//  TSContact.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseTransaction.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <AddressBook/AddressBook.h>
#endif

#import "TSInteraction.h"
#import "TSYapDatabaseObject.h"

typedef NS_OPTIONS(NSInteger, TSServicesAvailable){
    TSServiceRedPhone,
    TSServiceTextSecure
};

/**
 *  TSContacts always have one property, the identifier they are registered with on TextSecure. All the rest is optional.
 */

@interface TSContact : TSYapDatabaseObject

- (instancetype)initWithRecipientId:(NSString*)recipientId;

- (TSServicesAvailable)availableServices;
- (TSInteraction*)lastMessageWithTransaction:(YapDatabaseReadTransaction *)transaction;

#if TARGET_OS_IPHONE
- (ABRecordID*)addressBookID;
- (NSString*)firstName;
- (NSString*)lastName;
#endif

@end
