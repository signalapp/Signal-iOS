//
//  DemoDataModel.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

#import "JSQMessages.h"
#import "Contact.h"
#import "RecentCall.h"

static NSString * const kJSQDemoAvatarDisplayNameDylan = @"Dylan Bourgeois";
static NSString * const kJSQDemoAvatarDisplayNameFred = @"Frederic Jacobs";
static NSString * const kJSQDemoAvatarDisplayNameMoxie = @"Moxie Marlinspike";

static NSString * const kJSQDemoAvatarIdDylan = @"053496-4509-289";
static NSString * const kJSQDemoAvatarIdFred = @"468-768355-23123";
static NSString * const kJSQDemoAvatarIdMoxie = @"707-8956784-57";

@interface DemoDataModel : NSObject

@property (strong, nonatomic) NSMutableArray *messages;

@property (strong, nonatomic) JSQMessagesBubbleImage *outgoingBubbleImageData;

@property (strong, nonatomic) JSQMessagesBubbleImage *incomingBubbleImageData;

@property (strong, nonatomic) NSDictionary *users;


@property (nonatomic, strong) NSString * _sender ;
@property (nonatomic, strong) NSString * _snippet ;
@property (nonatomic, strong) NSArray * _conversation;
@property (nonatomic, strong) NSString * lastActionString;

+(DemoDataModel*)initModel:(NSUInteger)modelNumber;
+(Contact*)initFakeContacts:(NSUInteger)modelNumber;
+(RecentCall*)initRecentCall:(NSUInteger)modelNumber;



@end
