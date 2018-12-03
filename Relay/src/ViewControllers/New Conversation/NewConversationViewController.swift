//
//  NewConversationViewController.swift
//  Forsta
//
//  Created by Mark Descalzo on 5/24/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit
import CocoaLumberjack

class NewConversationViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource, UICollectionViewDelegate, UICollectionViewDataSource, UIGestureRecognizerDelegate, SlugCellDelegate, SlugLayoutDelegate {
    
    // Constants
    private let kMinInputHeight: CGFloat = 0.0
    private let kMaxInputHeight: CGFloat = 126.0
    
    private let kRecipientSectionIndex: Int = 0
    private let kTagSectionIndex: Int = 1
    
    private let kHiddenSectionIndex: Int = 0
    private let kMonitorSectionIndex: Int = 1
    
    private let kSelectorVisibleIndex: Int = 0
    private let kSelectorHiddenIndex: Int = 1
    
    private let kSlugRowHeight: CGFloat = 30.0
    
    // UI Elements
    @IBOutlet private weak var searchBar: UISearchBar?
    @IBOutlet private weak var contactTableView: UITableView?
    @IBOutlet private weak var slugCollectionView: UICollectionView?
    @IBOutlet private weak var exitButton: UIBarButtonItem?
    @IBOutlet private weak var goButton: UIBarButtonItem?
    @IBOutlet private weak var slugViewHeightConstraint: NSLayoutConstraint?
    @IBOutlet private weak var searchInfoLabel: UILabel?
    
    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshContentFromSource), for: .valueChanged)
        return control
    }()
    
    private let uiDBConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().dbReadConnection
    private let searchDBConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
    
    private var tagMappings: YapDatabaseViewMappings?
    
    // Properties
    private var selectedSlugs: Array<String> = Array()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.slugViewHeightConstraint?.constant = kMinInputHeight
        self.goButton?.tintColor = UIColor.FL_mediumLightGreen()
        
        self.searchBar?.placeholder = NSLocalizedString("SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", comment: "")
        self.searchInfoLabel?.text = NSLocalizedString("SEARCH_HELP_STRING", comment:"Informational string for tag lookups.")
        
        self.view.backgroundColor = UIColor.white
        
        // Slug view setup
        if let layout = self.slugCollectionView?.collectionViewLayout as? SlugViewLayout {
            layout.delegate = self
        }
        
        // Refresh control handling
        let refreshView = UIView()
        self.contactTableView?.insertSubview(refreshView, at: 0)
        refreshView.addSubview(self.refreshControl)
        
        // Set the mappings
        self.changeMappingsGroup(groups: [FLVisibleRecipientGroup, FLActiveTagsGroup ])
        self.updateGoButton()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.async {
            self.uiDBConnection.beginLongLivedReadTransaction()
            self.uiDBConnection.asyncRead({ (transaction) in
                self.tagMappings?.update(with: transaction)
            }, completionBlock: {
                self.updateFilteredMappings()
            })
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(yapDatabaseModified),
                                               name: NSNotification.Name.YapDatabaseModified,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(yapDatabaseModified),
                                               name: NSNotification.Name.YapDatabaseModifiedExternally,
                                               object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - CollectionView delegate/datasource methods
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return (self.selectedSlugs.count)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: SlugCell = self.slugCollectionView?.dequeueReusableCell(withReuseIdentifier: "SlugCell", for: indexPath) as! SlugCell
        cell.slugLabel.font = UIFont.systemFont(ofSize: 15.0)
        cell.slug = self.selectedSlugs[indexPath.row]
        cell.delegate = self
        
        return cell
    }
    
    // MARK: - Slug cell delegate methods
    func deleteButtonTappedOnSlug(sender: Any) {
        let slug = sender as! String
        
        self.removeSlug(slug: slug)
        self.contactTableView?.reloadData()
    }
    
    // MARK: - SlugViewLayout delegate methods
    func rowHeight() -> CGFloat {
        return self.kSlugRowHeight
    }
    
    func widthForSlug(at indexPath: IndexPath) -> CGFloat {
        let slugString = self.selectedSlugs[indexPath.item]
        let width = slugString.width(withConstrainedHeight: self.kSlugRowHeight, font: UIFont.systemFont(ofSize: 15.0))
        
        return width
    }
    
    func lines() -> CGFloat {
        return 2
    }


    
    // MARK: - TableView delegate/datasource methods
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactCell", for: indexPath) as! DirectoryCell
        
        let aThing = self.objectForIndexPath(indexPath: indexPath)
        
        if aThing.isKind(of: RelayRecipient.classForCoder()) {
            let recipient = aThing as! RelayRecipient
            
            DispatchQueue.global(qos: .default).async {
                cell.configureCell(recipient: recipient)
            }
            if (self.selectedSlugs.contains((recipient.flTag?.displaySlug)!)) {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
        } else if aThing.isKind(of: FLTag.classForCoder()) {
            let aTag = aThing as! FLTag
            
            DispatchQueue.global(qos: .default).async {
                cell.configureCell(aTag: aTag)
            }
            if (self.selectedSlugs.contains(aTag.displaySlug)) {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
        } else {
            return UITableViewCell()
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var tagSlug: String
        
        let aThing: NSObject = self.objectForIndexPath(indexPath: indexPath)
        
        if aThing.isKind(of: RelayRecipient.classForCoder()) {
            let recipient = aThing as! RelayRecipient
            tagSlug = (recipient.flTag?.displaySlug)!
        } else if aThing.isKind(of: FLTag.classForCoder()) {
            let aTag = aThing as! FLTag
            tagSlug = aTag.displaySlug
        } else {
            return
        }
        
        if (self.selectedSlugs.contains(tagSlug)) {
            self.removeSlug(slug: tagSlug)
        } else {
            self.addSlug(slug: tagSlug)
        }
        
        self.contactTableView?.reloadRows(at: [indexPath], with: .automatic)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        let number: NSNumber = NSNumber(value: (self.tagMappings?.numberOfSections())!)
        return Int(truncating: number)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let number: NSNumber = NSNumber(value: (self.tagMappings?.numberOfItems(inSection: UInt(section)))!)
        return Int(truncating: number)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.tableView(tableView, numberOfRowsInSection: section) > 0 {
            if section == kRecipientSectionIndex {
                return NSLocalizedString("THREAD_SECTION_CONTACTS", comment: "")
            } else if section == kTagSectionIndex {
                return NSLocalizedString("THREAD_SECTION_TAGS", comment: "")
            }
        }
        return nil
    }
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    
    @objc internal func yapDatabaseModified(notification: Notification) {
        let notfications = self.uiDBConnection.beginLongLivedReadTransaction()
        
        var sectionChanges = NSArray()
        var rowChanges = NSArray()
        
        let dbViewConnection: YapDatabaseViewConnection = self.uiDBConnection.ext(FLFilteredTagDatabaseViewExtensionName) as! YapDatabaseViewConnection
        dbViewConnection.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notfications, with: self.tagMappings!)
        
        // No related changes, bail...
        if (sectionChanges.count == 0 && rowChanges.count == 0) {
            return
        }
        
        self.contactTableView?.beginUpdates()
        
        for sectionChange in sectionChanges {
            let change = sectionChange as! YapDatabaseViewSectionChange
            switch change.type {
            case .insert:
                self.contactTableView?.insertSections(NSIndexSet(index: Int(change.index)) as IndexSet, with: .automatic)
            case .delete:
                self.contactTableView?.deleteSections(NSIndexSet(index: Int(change.index)) as IndexSet, with: .automatic)
            case .move:
                break
            case .update:
                self.contactTableView?.reloadSections(NSIndexSet(index: Int(change.index)) as IndexSet, with: .automatic)
            }
        }
        
        for rowChange in rowChanges {
            let change = rowChange as! YapDatabaseViewRowChange
            switch change.type {
                
            case .insert:
                self.contactTableView?.insertRows(at: [ change.newIndexPath! ], with: .automatic)
            case .delete:
                self.contactTableView?.deleteRows(at: [ change.indexPath! ], with: .automatic)
            case .move:
                self.contactTableView?.deleteRows(at: [ change.indexPath! ], with: .automatic)
                self.contactTableView?.insertRows(at: [ change.newIndexPath! ], with: .automatic)
            case .update:
                self.contactTableView?.reloadRows(at: [ change.indexPath! ], with: .automatic)
            }
        }
        self.contactTableView?.endUpdates()
    }
    
    // MARK: - UI Actions
    @IBAction func didPressGoButton(sender: Any) {
        var threadSlugs = String()
        
        for slug in self.selectedSlugs {
            if threadSlugs.count == 0 {
                threadSlugs.append(slug)
            } else {
                threadSlugs.append(" + \(slug)")
            }
        }
        CCSMCommManager.asyncTagLookup(with: threadSlugs,
                                       success: { results in
                                        self.storeUsersIn(results: results as NSDictionary)
                                        self.buildThreadWith(results: results as NSDictionary)
        },
                                       failure: { error in
                                        Logger.debug(String(format: "Tag Lookup failed with error: %@", error.localizedDescription))
                                        DispatchQueue.main.async {
                                            let alert = UIAlertController(title: nil,
                                                                          message: NSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: ""),
                                                                          preferredStyle: .actionSheet)
                                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                                                          style: .default,
                                                                          handler: nil))
                                            self.navigationController?.present(alert, animated: true, completion: nil)
                                        }

        })
        
    }

    @IBAction func didPressExitButton(sender: Any) {
        if (self.searchBar?.isFirstResponder)! {
            self.searchBar?.resignFirstResponder()
        }
        self.navigationController?.dismiss(animated: true, completion: { })
    }

    // MARK: - SearchBar delegate method
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.updateFilteredMappings()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        if (searchBar.text?.count)! > 0 {
            // process the string before sending to tagMath
            let originalString: String = searchBar.text!
            var searchString: String = String()
            for subString in originalString.components(separatedBy: .whitespacesAndNewlines) {
                if ((subString.count > 0) && !(subString == "@")) {
                    if (subString.substring(to: 1) == "@") {
                        searchString.append("\(subString) ")
                    } else {
                        searchString.append("@\(subString) ")
                    }
                }
            }
 
            // Do the lookup
            CCSMCommManager.asyncTagLookup(with: searchString,
                                           success: { (results) in
                                            let pretty = results["pretty"] as! String
                                            let warnings = results["warnings"] as! Array<NSDictionary>
                                            
                                            var badStrings = String()
                                            
                                            for warning in warnings {
                                                let position = warning["position"] as! Int
                                                let length = warning["length"] as! Int
                                                let range = Range(position ..< position+length)
                                                let badString = searchString.substring(with: range)
                                                badStrings.append("\(badString)\n")
                                            }
                                            if badStrings.count > 0 {
                                                DispatchQueue.main.async {
                                                    let message = "\(NSLocalizedString("TAG_NOT_FOUND_FOR", comment: "")):\n\(badStrings)"
                                                    let alert = UIAlertController(title: "",
                                                                                  message: message,
                                                                                  preferredStyle: .actionSheet)
                                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { action in /* Do nothin' */ }))
                                                    self.navigationController?.present(alert, animated: true, completion: nil)
                                                }
                                            }

                                            if pretty.count > 0 {
                                                do {
                                                let regex = try NSRegularExpression(pattern: "@[a-zA-Z0-9-.:]+(\\b|$)",
                                                                                    options: [.caseInsensitive, .anchorsMatchLines])
                                                    
                                                    let matches = regex.matches(in: pretty, options: [], range: NSRange(location: 0, length: pretty.count))
                                                    for match in matches {
                                                        if let swiftRange = Range(match.range, in :pretty) {
                                                            let newSlug = pretty[swiftRange.lowerBound..<swiftRange.upperBound]
                                                            self.addSlug(slug: String(newSlug))
                                                        }
                                                    }
                                                } catch {
                                                    // Bad regex?
                                                }
                                            }

                                            // Update the searchbar with remainder text
                                            var badStuff = String()
                                            for string in badStrings.components(separatedBy: .newlines) {
                                                badStuff.append("\(string) ")
                                            }
                                            DispatchQueue.main.async {
                                                searchBar.text = badStuff
                                                self.updateFilteredMappings()
                                            }
                                            // take this opportunity to store any userids
                                            let userids = results["userids"] as! Array<String>
                                            if userids.count > 0 {
                                                NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                                                                object: self, userInfo: ["userIds" : userids])
                                            }
            },
                                           failure:{ (error) in
                                            Logger.debug("Tag Lookup failed with error: \(error.localizedDescription)")
                                            DispatchQueue.main.async {
                                                let alert = UIAlertController(title: "",
                                                                              message: NSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: ""),
                                                                              preferredStyle: .actionSheet)
                                                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                                                              style: .default,
                                                                              handler: nil))
                                                self.navigationController?.present(alert, animated: true, completion: nil)
                                            }
            })
        }
            
    }
    
    // MARK: - Thread creation methods
    private func storeUsersIn(results: NSDictionary) {
        DispatchQueue.global(qos: .background).async {
            let usersIds: Array<String> = results.object(forKey: "userids") as! Array<String>
            
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                            object: self, userInfo: ["userIds" : usersIds])
        }
    }
    
    private func buildThreadWith(results: NSDictionary) {
        let userIds = results.object(forKey: "userids") as! Array<String>
        
        // Verify myself is included
        if !(userIds.contains(TSAccountManager.sharedInstance().selfRecipient().uniqueId)) {
            // If not, add self and run again
            var pretty = results.object(forKey: "pretty") as! String
            let mySlug = TSAccountManager.sharedInstance().selfRecipient().flTag?.slug
            pretty.append(" + @\(mySlug!)")
            
            CCSMCommManager.asyncTagLookup(with: pretty, success: { newResults in
                self.buildThreadWith(results: newResults as NSDictionary)
            }, failure: { error in
                Logger.debug(String(format: "Tag Lookup failed with error: %@", error.localizedDescription))
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: nil,
                                                  message: NSLocalizedString("ERROR_DESCRIPTION_SERVER_FAILURE", comment: ""),
                                                  preferredStyle: .actionSheet)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                                  style: .default,
                                                  handler: nil))
                    self.navigationController?.present(alert, animated: true, completion: nil)
                }
            })
        } else {
            // build thread and go
            let thread = TSThread.getOrCreateThread(withParticipants: userIds)
            thread.type = FLThreadTypeConversation
            thread.prettyExpression = results.object(forKey: "pretty") as? String
            thread.universalExpression = results.object(forKey: "universal") as? String
            thread.save()

            NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                            object: self, userInfo: ["userIds" : userIds])
            DispatchQueue.main.async {
                self.navigationController?.dismiss(animated: true, completion: {
                    SignalApp.shared().presentConversation(for: thread, action: .compose)
                })
            }
        }
    }

    // MARK: - Private worker methods
    private func updateFilteredMappings() {
        let filterString = self.searchBar?.text?.lowercased()
        
        let filtering = YapDatabaseViewFiltering.withObjectBlock { (transaction, group, collection, key, object) -> Bool in
            let obj: NSObject = object as! NSObject
            if obj.isKind(of: RelayRecipient.classForCoder()) || obj.isKind(of: FLTag.classForCoder()) {
                if (filterString?.count)! > 0 {
                    if obj.isKind(of: FLTag.classForCoder()) {
                        let aTag: FLTag = obj as! FLTag
                        return ((aTag.displaySlug.lowercased() as NSString).contains(filterString!) ||
                            (aTag.slug.lowercased() as NSString).contains(filterString!) ||
                            (aTag.tagDescription!.lowercased() as NSString).contains(filterString!) ||
                            (aTag.orgSlug.lowercased() as NSString).contains(filterString!))
                        
                    } else if obj.isKind(of: RelayRecipient.classForCoder()) {
                        let recipient: RelayRecipient = obj as! RelayRecipient
                        return ( (recipient.fullName().lowercased() as NSString).contains(filterString!) ||
                            (recipient.flTag!.displaySlug.lowercased() as NSString).contains(filterString!) ||
                            (recipient.orgSlug!.lowercased() as NSString).contains(filterString!))
                    } else {
                        return false
                    }
                } else {
                    return true
                }
            }
            return false
        }
        self.searchDBConnection.asyncReadWrite({ (transaction) in
            let filteredViewTransaction = transaction.ext(FLFilteredTagDatabaseViewExtensionName) as! YapDatabaseFilteredViewTransaction
            filteredViewTransaction.setFiltering(filtering, versionTag: filterString)
        }) {
            self.updateContactsView()
        }
    }
    
    private func removeSlug(slug: String) {
        var slugString = slug as String
        
        if !(slug.substring(to:  1) == "@") {
            slugString = String.init(format: "@%@", slug)
        }
        
        let index = self.selectedSlugs.index(of: slugString)
        self.selectedSlugs.remove(at: index!)
        
        DispatchQueue.main.async {
            // Refresh collection view
            self.slugCollectionView?.reloadData()
            self.updateGoButton()
            self.resizeSlugView(scroll: false)
        }
    }
    
    private func addSlug(slug: String) {
        var slugString = slug as String
        
        if !(slug.substring(to:  1) == "@") {
            slugString = String.init(format: "@%@", slug)
        }
        
        self.selectedSlugs.append(slugString)
        
        DispatchQueue.main.async {
            // Refresh collection view
            self.slugCollectionView?.reloadData()
            self.updateGoButton()
            self.resizeSlugView(scroll: true)
        }
    }
    
    private func resizeSlugView(scroll: Bool) {
        // Small delay to avoid race condition where we attempted to resize before the new size was calculated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
            UIView.animate(withDuration: 0.25, animations: {
                if (self.slugCollectionView?.contentSize.height)! > self.kMaxInputHeight {
                    self.slugViewHeightConstraint?.constant = self.kMaxInputHeight
                } else {
                    self.slugViewHeightConstraint?.constant = (self.slugCollectionView?.contentSize.height)!
                }

            })
            if scroll {
                let bottomOffset = CGPoint(x: 0, y: (self.slugCollectionView?.contentSize.height)! - (self.slugCollectionView?.bounds.size.height)!)
                if bottomOffset != self.slugCollectionView?.contentOffset {
                    self.slugCollectionView?.setContentOffset(bottomOffset, animated: false)
                }
            }

        })
    }
    
    private func objectForIndexPath(indexPath: IndexPath) -> NSObject {
        
        var viewExtensionName = FLTagDatabaseViewExtensionName
        if searchBar?.text?.count ?? 0 > 0 {
            viewExtensionName = FLFilteredTagDatabaseViewExtensionName
        }

        var object = NSObject()
        self.uiDBConnection.read { transaction in
            let viewTransaction: YapDatabaseViewTransaction = transaction.ext(viewExtensionName) as! YapDatabaseViewTransaction
            object = viewTransaction.object(at: indexPath, with: self.tagMappings!) as! NSObject
        }
        return object
    }
    
    @objc private func refreshContentFromSource() {
        DispatchQueue.main.async {
            self.refreshControl.beginRefreshing()
            FLContactsManager.shared.refreshCCSMRecipients()
            self.refreshControl.endRefreshing()
        }
    }
    
    private func updateGoButton() {
        DispatchQueue.main.async {
            if self.selectedSlugs.count == 0 {
                self.goButton?.isEnabled = false
            } else {
                self.goButton?.isEnabled = true
            }
        }
    }
    
    private func updateContactsView() {
        DispatchQueue.main.async {
            if self.tagMappings?.numberOfItemsInAllGroups() == 0 {
                self.searchInfoLabel?.isHidden = false
                self.contactTableView?.isHidden = true
            } else {
                self.searchInfoLabel?.isHidden = true
                self.contactTableView?.isHidden = false
            }
            self.contactTableView?.reloadData()
        }
    }
    
    private func changeMappingsGroup(groups: Array<String>) {
        self.uiDBConnection.beginLongLivedReadTransaction()
        self.tagMappings = YapDatabaseViewMappings(groups: groups , view: FLFilteredTagDatabaseViewExtensionName)
        
        for group in groups {
            self.tagMappings?.isReversed(forGroup: group)
        }
        
        DispatchQueue.main.async {
            self.uiDBConnection.asyncRead({ (transaction) in
                self.tagMappings?.update(with: transaction)
            }, completionBlock: {
                self.updateContactsView()
            })
        }
    }
}

extension String {
    // Source: https://stackoverflow.com/questions/39677330/how-does-string-substring-work-in-swift
    func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }
    
    func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return String(self[fromIndex...])
    }
    
    func substring(to: Int) -> String {
        let toIndex = index(from: to)
        return String(self[..<toIndex])
    }
    
    func substring(with r: Range<Int>) -> String {
        let startIndex = index(from: r.lowerBound)
        let endIndex = index(from: r.upperBound)
        return String(self[startIndex..<endIndex])
    }

    // https://stackoverflow.com/questions/30450434/figure-out-size-of-uilabel-based-on-string-in-swift#30450559
    func height(withConstrainedWidth width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [.font : font], context: nil)
        
        return ceil(boundingBox.height)
    }
    
    func width(withConstrainedHeight height: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [.font : font], context: nil)
        
        return ceil(boundingBox.width)
    }
}
