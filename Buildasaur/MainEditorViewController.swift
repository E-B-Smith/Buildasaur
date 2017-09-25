//
//  MainEditorViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit
import ReactiveSwift
import BuildaUtils

protocol EditorViewControllerFactoryType {
    
    func supplyViewControllerForState(_ state: EditorState, context: EditorContext) -> EditableViewController?
}

class MainEditorViewController: PresentableViewController {
    
    var factory: EditorViewControllerFactoryType!
    let context = MutableProperty<EditorContext>(EditorContext())
    
    @IBOutlet weak var containerView: NSView!
    
    @IBOutlet weak var previousButton: NSButton!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    
    //state and animated?
    let state = MutableProperty<(EditorState, Bool)>((.noServer, false))

    var _contentViewController: EditableViewController?
    
    @IBAction func previousButtonClicked(_ sender: AnyObject) {
        //state machine - will be disabled on the first page,
        //otherwise will say "Previous" and move one back in the flow
        self.previous(animated: false)
    }
    
    @IBAction func nextButtonClicked(_ sender: AnyObject) {
        //state machine - will say "Save" and dismiss if on the last page,
        //otherwise will say "Next" and move one forward in the flow
        self.next(animated: true)
    }
    
    @IBAction func cancelButtonClicked(_ sender: AnyObject) {
        //just a cancel button.
        self.cancel()
    }
    
    func loadInState(_ state: EditorState) {
        self.state.value = (state, false)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.containerView.wantsLayer = true
        self.containerView.layer!.backgroundColor = NSColor.lightGray.cgColor
        
        self.setupBindings()
        
        //HACK: hack for debugging - jump ahead
//        self.state.value = (.EditingSyncer, false)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        if let window = self.view.window {
            let size = CGSize(width: 600, height: 422)
            window.minSize = size
            window.maxSize = size
        }
    }
    
    // moving forward and back
    
    func previous(animated: Bool) {
        
        //check with the current controller first
        if let content = self._contentViewController {
            if !content.shouldGoPrevious() {
                return
            }
        }
        
        self._previous(animated: animated)
    }
    
    //not verified that vc is okay with it
    func _previous(animated: Bool) {
        
        if let previous = self.state.value.0.previous() {
            self.state.value = (previous, animated)
        } else {
            //we're at the beginning, dismiss?
        }
    }
    
    func next(animated: Bool) {
        
        //check with the current controller first
        if let content = self._contentViewController {
            if !content.shouldGoNext() {
                return
            }
        }
        
        self._next(animated: animated)
    }
    
    func _next(animated: Bool) {
        
        if let next = self.state.value.0.next() {
            self.state.value = (next, animated)
        } else {
            //we're at the end, dismiss?
        }
    }
    
    func cancel() {
        
        //check with the current controller first
        if let content = self._contentViewController {
            if !content.shouldCancel() {
                return
            }
        }
        
        self._cancel()
    }
    
    func _cancel() {
        
        self.dismissWindow()
    }
    
    //setup RAC
    
    fileprivate func setupBindings() {
        
        self.state
            .producer
            .combinePrevious((.initial, false)) //keep history
            .filter { $0.0.0 != $0.1.0 } //only take changes
            .startWithValues { [weak self] in
                self?.stateChanged(fromState: $0.0, toState: $1.0, animated: $1.1)
        }
        
        self.state.producer.map { $0.0 == .noServer }.startWithValues { [weak self] in
            if $0 {
                self?.previousButton.isEnabled = false
            }
        }
        
        //create a title
        self.context.producer.map { context -> String in
            let triplet = context.configTriplet!
            var comps = [String]()
            if let host = triplet.server?.host {
                comps.append(host)
            } else {
                comps.append("New Server")
            }
            if let projectName = triplet.project?.name {
                comps.append(projectName)
            } else {
                comps.append("New Project")
            }
            if let templateName = triplet.buildTemplate?.name {
                comps.append(templateName)
            } else {
                comps.append("New Build Template")
            }
            return comps.joined(separator: " + ")
        }.startWithValues { [weak self] in
            self?.title = $0
        }
    }
    
    //state manipulation
    
    fileprivate func stateChanged(fromState: EditorState, toState: EditorState, animated: Bool) {

        let context = self.context.value
        if let viewController = self.factory.supplyViewControllerForState(toState, context: context) {
            self.setContentViewController(viewController, animated: animated)
        } else {
            self.dismissWindow()
        }
    }
    
    internal func dismissWindow() {
        self.presentingDelegate?.closeWindowWithViewController(self)
    }
}

