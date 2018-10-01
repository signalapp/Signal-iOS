//
//  AnnouncementDetailViewController.m
//  Forsta
//
//  Created by Mark Descalzo on 1/30/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

// TODO:  Define a YapDatabaseView to handle the content in this view controller.

#import "AnnouncementDetailViewController.h"
//#import "FLDirectoryCell.h"
#import "Relay-Swift.h"
//#import "TSIncomingMessage.h"
//#import "RelayRecipient.h"
//#import "TSThread.h"

@import RelayServiceKit;

#define kFromSectionIndex 0
#define kToSectionIndex 1

@interface AnnouncementDetailViewController ()

@property (nonatomic, strong) RelayRecipient *sender;
@property (nonatomic, strong) NSArray <RelayRecipient *> *recipients;
@property YapDatabaseConnection *uiConnection;

@end

@implementation AnnouncementDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    self.title = NSLocalizedString(@"ANNOUNCEMENT_DETAIL_TITLE", nil);
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    self.uiConnection = [OWSPrimaryStorage.sharedManager dbReadConnection];
    [self.uiConnection beginLongLivedReadTransaction];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:nil];
}

-(void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications
-(void)yapDatabaseModified:(NSNotification *)notification {
    NSArray *notifications = [self.uiConnection beginLongLivedReadTransaction];
    
    if ([notifications count] == 0) {
        return; // already processed commit
    }
    BOOL needsRefresh = NO;
    TSThread *thread = self.message.thread;
    if ([self.uiConnection hasChangeForKey:self.message.thread.uniqueId
                              inCollection:[TSThread collection]
                           inNotifications:notifications] ||
        [self.uiConnection hasChangeForKey:self.message.uniqueId
                              inCollection:[TSMessage collection]
                           inNotifications:notifications]) {
            needsRefresh = YES;
        }
    
    for (NSString *uid in self.message.thread.participantIds) {
        if ([self.uiConnection hasChangeForKey:uid.uppercaseString
                                  inCollection:[RelayRecipient collection]
                               inNotifications: notifications]) {
            needsRefresh = YES;
        }
    }
    
    if (needsRefresh) {
        self.sender = nil;
        self.recipients = nil;
        [self.tableView reloadData];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case kFromSectionIndex:
        {
            return 1;
        }
            break;
        default:
            return (NSInteger)self.recipients.count;
            break;
    }
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DirectoryCell *cell = (DirectoryCell *)[tableView dequeueReusableCellWithIdentifier:@"aCell" forIndexPath:indexPath];
    
    switch (indexPath.section) {
        case kFromSectionIndex:
        {
            [cell configureCellWithRecipient:self.sender];
        }
            break;
        case kToSectionIndex:
        {
            [cell configureCellWithRecipient:[self.recipients objectAtIndex:(NSUInteger)indexPath.row]];
        }
            break;
        default:
            break;
    }
    // Configure the cell...
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:section];
    if (rows > 0) {
        if (section == kFromSectionIndex) {
            return NSLocalizedString(@"ANNOUNCEMENT_FROM_SECTION", nil);
        } else if (section == kToSectionIndex) {
            return NSLocalizedString(@"ANNOUNCEMENT_TO_SECTION", nil);
        }
    }
    return nil;
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

-(RelayRecipient *)sender
{
    if (_sender == nil) {
        if ([self.message isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incMessage = (TSIncomingMessage *)self.message;
            _sender = [FLContactsManager.shared recipientWithId:incMessage.authorId];
        } else {
            _sender = TSAccountManager.sharedInstance.selfRecipient;
        }
    }
    return _sender;
}

-(NSArray <RelayRecipient *> *)recipients
{
    if (_recipients == nil) {
        NSMutableArray *holdingTank = [NSMutableArray new];
        for (NSString *uid in self.message.thread.participantIds) {
            RelayRecipient *newRecipient = [FLContactsManager.shared recipientWithId:uid];
            if (newRecipient) {
                [holdingTank addObject:newRecipient];
            } else {
                [NSNotificationCenter.defaultCenter postNotificationName:FLRecipientsNeedRefreshNotification
                                                                  object:nil
                                                                userInfo:@{ @"userIds" : @[ uid ] }];
            }
        }
        _recipients = [NSArray arrayWithArray:holdingTank];
    }
    return _recipients;
}

@end
