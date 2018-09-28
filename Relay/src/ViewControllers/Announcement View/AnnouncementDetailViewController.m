//
//  AnnouncementDetailViewController.m
//  Forsta
//
//  Created by Mark Descalzo on 1/30/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

#import "AnnouncementDetailViewController.h"
#import "FLDirectoryCell.h"
#import "TSIncomingMessage.h"
#import "SignalRecipient.h"
#import "TSThread.h"

#define kFromSectionIndex 0
#define kToSectionIndex 1

@interface AnnouncementDetailViewController ()

@property (nonatomic, strong) SignalRecipient *sender;
@property (nonatomic, strong) NSArray <SignalRecipient *> *recipients;

@end

@implementation AnnouncementDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    self.title = NSLocalizedString(@"ANNOUNCEMENT_DETAIL_TITLE", nil);
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
    FLDirectoryCell *cell = (FLDirectoryCell *)[tableView dequeueReusableCellWithIdentifier:@"aCell" forIndexPath:indexPath];
    
    switch (indexPath.section) {
        case kFromSectionIndex:
        {
            [cell configureCellWithContact:self.sender];
        }
            break;
        case kToSectionIndex:
        {
            [cell configureCellWithContact:[self.recipients objectAtIndex:(NSUInteger)indexPath.row]];
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

-(SignalRecipient *)sender
{
    if (_sender == nil) {
        if ([self.message isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incMessage = (TSIncomingMessage *)self.message;
            _sender = [Environment.getCurrent.contactsManager recipientWithUserId:incMessage.authorId];
        } else {
            _sender = TSAccountManager.sharedInstance.myself;
        }
    }
    return _sender;
}

-(NSArray <SignalRecipient *> *)recipients
{
    if (_recipients == nil) {
        NSMutableArray *holdingTank = [NSMutableArray new];
        for (NSString *uid in self.message.thread.participants) {
            SignalRecipient *newRecipient = [Environment.getCurrent.contactsManager recipientWithUserId:uid];
            if (newRecipient) {
                [holdingTank addObject:newRecipient];
            }
        }
        _recipients = [NSArray arrayWithArray:holdingTank];
    }
    return _recipients;
}

@end
