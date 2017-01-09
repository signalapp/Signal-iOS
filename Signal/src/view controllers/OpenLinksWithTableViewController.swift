//
//  OpenLinksWithTableViewController.swift
//  Signal
//
//  Created by Adam Kunicki on 12/22/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
class OpenLinksWithTableViewController: UITableViewController {
    private let browsers = WebBrowsers.all()
    private var selectedBrowser: WebBrowser = WebBrowsers.safari()
    
    override func viewDidLoad() {
        selectedBrowser = getSelectedBrowserFromPreferences()
        
        let selectedIndexPath = IndexPath(row: selectedBrowser.index, section: 0)
        tableView.selectRow(at: selectedIndexPath, animated: false, scrollPosition: .none)

    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return browsers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BrowserCell", for: indexPath)

        cell.textLabel?.text = browsers[indexPath.row].label
        cell.selectionStyle = .none
        
        if !(selectedBrowser.isInstalled() ?? false) {
            tableView.deselectRow(at: indexPath, animated: false)
            revertToSafari()
        }
        
        if (selectedBrowser.index == indexPath.row) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none

        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedBrowser = browsers[indexPath.row]
        Environment.preferences().setOpenLinksWith(selectedBrowser.index as NSNumber)
        
        let selectedCell = tableView.cellForRow(at: indexPath)
        selectedCell?.accessoryType = .checkmark
        
        performSegue(withIdentifier: "unwindFromOpenLinksWith", sender: self)
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let deselectedCell = tableView.cellForRow(at: indexPath)
        deselectedCell?.accessoryType = .none
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // hide browser cell if not installed
        let browserForCell = browsers[indexPath.row]
        if (browserForCell.isInstalled()) {
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
        
        return 0.0
    }
    
    private func revertToSafari() {
        selectedBrowser = WebBrowsers.safari()
        tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
    }
    
    private func getSelectedBrowserFromPreferences() -> WebBrowser {
        let selectedBrowserIndex = Int(Environment.preferences().getOpenLinksWith())
        return browsers[selectedBrowserIndex]
    }
    
    // MARK: public methods
    
    func getSelectedBrowser() -> WebBrowser {
        // Check if browser is still valid
        if (!selectedBrowser.isInstalled()) {
            revertToSafari()
        }
        return selectedBrowser
    }
}
