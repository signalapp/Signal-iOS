//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSSoundSettingsViewController : OWSTableViewController <UIDocumentPickerDelegate>

// This property is optional.  If it is not set, we are
// editing the global notification sound.
@property (nonatomic, nullable) TSThread *thread;

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls;

@end

NS_ASSUME_NONNULL_END
