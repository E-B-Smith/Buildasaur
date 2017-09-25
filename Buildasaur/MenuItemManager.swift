//
//  MenuItemManager.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 15/05/15.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit

class MenuItemManager : NSObject, NSMenuDelegate {
    
    var syncerManager: SyncerManager!
    
    fileprivate var statusItem: NSStatusItem?
    fileprivate var firstIndexLastSyncedMenuItem: Int!
    
    func setupMenuBarItem() {
        
        let statusBar = NSStatusBar.system
        
        let statusItem = statusBar.statusItem(withLength: 32)
        statusItem.title = ""
        statusItem.image = NSImage(named: NSImage.Name(rawValue: "icon"))
        statusItem.highlightMode = true
        
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Buildasaur", action: #selector(AppDelegate.showMainWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        self.firstIndexLastSyncedMenuItem = menu.numberOfItems
        
        statusItem.menu = menu
        menu.delegate = self
        self.statusItem = statusItem
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        
        //update with last sync/statuses
        let syncers = self.syncerManager.syncers

        //remove items for existing syncers
        let itemsForSyncers = menu.numberOfItems - self.firstIndexLastSyncedMenuItem
        let diffItems = syncers.count - itemsForSyncers
        
        //this many items need to be created or destroyed
        if diffItems > 0 {
            for _ in 0..<diffItems {
                menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            }
        } else if diffItems < 0 {
            for _ in 0..<abs(diffItems) {
                menu.removeItem(at: menu.numberOfItems-1)
            }
        }
        
        //now we have the right number, update the data
        let texts = syncers
            .sorted { (o1, o2) in o1.project.serviceRepoName() ?? "" < o2.project.serviceRepoName() ?? "" }
            .map({ (syncer: StandardSyncer) -> String in
            
            let state = SyncerStatePresenter.stringForState(syncer.state.value, active: syncer.active)
            
            let repo: String
            if let repoName = syncer.project.serviceRepoName() {
                repo = repoName
            } else {
                repo = "???"
            }
            
            let time: String
            if let lastSuccess = syncer.lastSuccessfulSyncFinishedDate, syncer.active {
                time = "last synced \(lastSuccess.nicelyFormattedRelativeTimeToNow())"
            } else {
                time = ""
            }
            
            let report = "\(repo) \(state) \(time)"
            return report
        })
        
        //fill into items
        for (i, text) in texts.enumerated() {
            let idx = self.firstIndexLastSyncedMenuItem + i
            let item = menu.item(at: idx)
            item?.title = text
        }
    }

}
