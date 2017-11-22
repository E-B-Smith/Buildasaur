//
//  AppDelegate.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 12/12/2014.
//  Copyright (c) 2014 Honza Dvorsky. All rights reserved.
//

import Cocoa

/*
 Please report any crashes on GitHub, I may optionally ask you to email them to me. Thanks!
 You can find them at ~/Library/Logs/DiagnosticReports/Buildasaur-*
 Also, you can find the logs at ~/Library/Application Support/Buildasaur/Logs
 */

import BuildaUtils
import XcodeServerSDK
import BuildaKit
import Fabric
import Crashlytics
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var syncerManager: SyncerManager!

    let menuItemManager = MenuItemManager()
    let serviceAuthenticator = ServiceAuthenticator()

    var storyboardLoader: StoryboardLoader!

    var dashboardViewController: DashboardViewController?
    var dashboardWindow: NSWindow?
    var windows: Set<NSWindow> = []
    var updater: SUUpdater?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        #if TESTING
            print("Testing configuration, not launching the app")
        #else
            self.setup()
        #endif
    }

    func setup() {

        //uncomment when debugging autolayout
        //        let defs = NSUserDefaults.standardUserDefaults()
        //        defs.setBool(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        //        defs.synchronize()

        self.setupSparkle()
        self.setupURLCallback()
        self.setupPersistence()

        self.storyboardLoader = StoryboardLoader(storyboard: NSStoryboard.mainStoryboard)
        self.storyboardLoader.delegate = self

        self.menuItemManager.syncerManager = self.syncerManager
        self.menuItemManager.setupMenuBarItem()

        let dashboard = self.createInitialViewController()
        self.dashboardViewController = dashboard
        self.presentViewControllerInUniqueWindow(dashboard)
        self.dashboardWindow = self.windowForPresentableViewControllerWithIdentifier("dashboard")!.0
    }

    func setupSparkle() {
        #if RELEASE
            self.updater = SUUpdater.shared()
            self.updater!.delegate = self
        #endif
    }

    func migratePersistence(_ persistence: Persistence) {

        let fileManager = FileManager.default
        //before we create the storage manager, attempt migration first
        let migrator = CompositeMigrator(persistence: persistence)
        if migrator.isMigrationRequired() {

            print("Migration required, launching migrator")

            do {
                try migrator.attemptMigration()
            } catch {
                print("Migration failed with error \(error), wiping folder...")

                //wipe the persistence. start over if we failed to migrate
                _ = try? fileManager.removeItem(at: persistence.readingFolder)
            }
            print("Migration finished")
        } else {
            print("No migration necessary, skipping...")
        }
    }

    func setupPersistence() {

        let persistence = PersistenceFactory.createStandardPersistence()

        //migration
        self.migratePersistence(persistence)

        //setup logging
        Logging.setup(persistence: persistence, alsoIntoFile: true)

        //create storage manager
        let storageManager = StorageManager(persistence: persistence)
        let factory = SyncerFactory()
        factory.syncerLifetimeChangeObserver = storageManager
        let loginItem = LoginItem()
        let syncerManager = SyncerManager(storageManager: storageManager, factory: factory, loginItem: loginItem)
        self.syncerManager = syncerManager

        if let crashlyticsOptOut = storageManager.config["crash_reporting_opt_out"] as? Bool, crashlyticsOptOut {
            Log.info("User opted out of crash reporting")
        } else {
            #if DEBUG
                Log.info("Not starting Crashlytics in debug mode.")
            #else
                Log.info("Will send crashlogs to Crashlytics. To opt out add `\"crash_reporting_opt_out\" = true` to ~/Library/Application Support/Buildasaur/Config.json")
                UserDefaults.standard.register(defaults: [
                    "NSApplicationCrashOnExceptions": true
                    ])
                Fabric.with([Crashlytics.self])
            #endif
        }
    }

    func createInitialViewController() -> DashboardViewController {

        let dashboard: DashboardViewController = self.storyboardLoader
            .presentableViewControllerWithStoryboardIdentifier("dashboardViewController", uniqueIdentifier: "dashboard", delegate: self)
        dashboard.loadView()
        dashboard.syncerManager = self.syncerManager
        dashboard.serviceAuthenticator = self.serviceAuthenticator
        return dashboard
    }

    func handleUrl(_ url: URL) {

        print("Handling incoming url")

        if url.host == "oauth-callback" {
            self.serviceAuthenticator.handleUrl(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {

        self.showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {

        self.showMainWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {

        let runningCount = self.syncerManager.syncers.filter({ $0.active }).count
        if runningCount > 0 {

            let confirm = "Are you sure you want to quit Buildasaur? This would stop \(runningCount) running syncers."
            UIUtils.showAlertAskingConfirmation(confirm, dangerButton: "Quit") { quit in
                NSApp.reply(toApplicationShouldTerminate: quit)
            }

            return NSApplication.TerminateReply.terminateLater
        } else {
            return NSApplication.TerminateReply.terminateNow
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {

        //stop syncers properly
        self.syncerManager.stopSyncers()
    }

    // MARK: Showing Window on Reactivation

    @objc func showMainWindow() {

        NSApp.activate(ignoringOtherApps: true)

        //first window. i wish there was a nicer way (please someone tell me there is)
        if NSApp.windows.count < 3 {
            self.dashboardWindow?.makeKeyAndOrderFront(self)
        }
    }

    //Sparkle magic
    func checkForUpdates(_ sender: AnyObject!) {
        self.updater?.checkForUpdates(sender)
    }
}

extension AppDelegate: SUUpdaterDelegate {

    func updater(_ updater: SUUpdater, willInstallUpdate item: SUAppcastItem) {
        self.syncerManager.heartbeatManager?.willInstallSparkleUpdate()
    }
}

extension AppDelegate {

    func setupURLCallback() {

        // listen to scheme url
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(AppDelegate.handleGetURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor!, withReplyEvent: NSAppleEventDescriptor!) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: urlString) {

            //handle url
            self.handleUrl(url)
        }
    }
}

extension AppDelegate: PresentableViewControllerDelegate {

    func configureViewController(_ viewController: PresentableViewController) {

        //
    }

    func presentViewControllerInUniqueWindow(_ viewController: PresentableViewController) {

        //last chance to config
        self.configureViewController(viewController)

        //make sure we're the delegate
        viewController.presentingDelegate = self

        //check for an existing window
        let identifier = viewController.uniqueIdentifier
        var newWindow: NSWindow?

        if let existingPair = self.windowForPresentableViewControllerWithIdentifier(identifier) {
            newWindow = existingPair.0
        } else {
            newWindow = NSWindow(contentViewController: viewController)
            newWindow?.autorecalculatesKeyViewLoop = true

            //if we already are showing some windows, let's cascade the new one
            if !self.windows.isEmpty {
                //find the right-most window and cascade from it
                let rightMost = self.windows.reduce(CGPoint(x: 0.0, y: 0.0), { (right: CGPoint, window: NSWindow) -> CGPoint in
                    let origin = window.frame.origin
                    if origin.x > right.x {
                        return origin
                    }
                    return right
                })
                let newOrigin = newWindow!.cascadeTopLeft(from: rightMost)
                newWindow?.setFrameTopLeftPoint(newOrigin)
            }
        }

        guard let window = newWindow else { fatalError("Unable to create window") }

        window.delegate = self
        self.windows.insert(window)
        window.makeKeyAndOrderFront(self)
    }

    func closeWindowWithViewController(_ viewController: PresentableViewController) {

        if let window = self.windowForPresentableViewControllerWithIdentifier(viewController.uniqueIdentifier)?.0 {

            if window.delegate?.windowShouldClose!(window) ?? true {
                window.close()
            }
        }
    }
}

extension AppDelegate: StoryboardLoaderDelegate {

    func windowForPresentableViewControllerWithIdentifier(_ identifier: String) -> (NSWindow, PresentableViewController)? {

        for window in self.windows {

            guard let viewController = window.contentViewController else { continue }
            guard let presentableViewController = viewController as? PresentableViewController else { continue }
            if presentableViewController.uniqueIdentifier == identifier {
                return (window, presentableViewController)
            }
        }
        return nil
    }

    func storyboardLoaderExistingViewControllerWithIdentifier(_ identifier: String) -> PresentableViewController? {
        //look through our windows and their view controllers to see if we can't find this view controller
        let pair = self.windowForPresentableViewControllerWithIdentifier(identifier)
        return pair?.1
    }
}

extension AppDelegate: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {

        self.windows.remove(sender)

        //TODO: based on the editing state, if editing VC (cancel/save)
        return true
    }
}
