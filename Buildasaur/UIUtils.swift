//
//  UIUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 07/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaUtils

open class UIUtils {
    
    open class func showAlertWithError(_ error: Error) {
        
        let alert = self.createErrorAlert(error)
        self.presentAlert(alert, completion: { (resp) -> () in
            //
        })
    }
    
    open class func showAlertAskingConfirmation(_ text: String, dangerButton: String, completion: @escaping (_ confirmed: Bool) -> ()) {
        
        let buttons = ["Cancel", dangerButton]
        self.showAlertWithButtons(text, buttons: buttons) { (tappedButton) -> () in
            completion(dangerButton == tappedButton)
        }
    }

    
    open class func showAlertAskingForRemoval(_ text: String, completion: @escaping (_ remove: Bool) -> ()) {
        self.showAlertAskingConfirmation(text, dangerButton: "Remove", completion: completion)
    }
    
    open class func showAlertWithButtons(_ text: String, buttons: [String], style: NSAlert.Style? = nil, completion: @escaping (_ tappedButton: String) -> ()) {
        
        let alert = self.createAlert(text, style: style)
        
        buttons.forEach { alert.addButton(withTitle: $0) }
        
        self.presentAlert(alert, completion: { (resp) -> () in
            
            //some magic where indices are starting at 1000... so subtract 1000 to get the array index of tapped button
            let idx: Int = resp.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let buttonText = buttons[idx]
            completion(buttonText)
        })
    }
    
    open class func showAlertWithText(_ text: String, style: NSAlert.Style? = nil, completion: ((NSApplication.ModalResponse) -> ())? = nil) {

        let alert = self.createAlert(text, style: style)
        self.presentAlert(alert, completion: completion)
    }
    
    fileprivate class func createErrorAlert(_ error: Error) -> NSAlert {
        return NSAlert(error: error as NSError)
    }
    
    fileprivate class func createAlert(_ text: String, style: NSAlert.Style?) -> NSAlert {
        
        let alert = NSAlert()
        
        alert.alertStyle = style ?? .informational
        alert.messageText = text
        
        return alert
    }
    
    fileprivate class func presentAlert(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> ())?) {
        
        if let _ = NSApp.windows.first {
            let resp = alert.runModal()
            completion?(resp)
//            alert.beginSheetModalForWindow(window, completionHandler: completion)
        } else {
            //no window to present in, at least print
            Log.info("Alert: \(alert.messageText)")
        }
    }
}

extension NSPopUpButton {
    
    public func replaceItems(_ newItems: [String]) {
        self.removeAllItems()
        self.addItems(withTitles: newItems)
    }
}

extension NSButton {
    
    public var on: Bool {
        get { return self.state == .on }
        set { self.state = newValue ? .on : .off }
    }
}
