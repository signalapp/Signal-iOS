//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OWSContactsManager.h"

/**
 *
 * ContactTableViewCell displays a contact from a Contact object.
 *
 */

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;

@interface ContactTableViewCell : UITableViewCell

+ (CGFloat)rowHeight;

- (void)configureWithContact:(Contact *)contact contactsManager:(OWSContactsManager *)contactsManager;

@end

NS_ASSUME_NONNULL_END
