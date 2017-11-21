//
//  MainEditorViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit
import BuildaUtils

protocol EditorViewControllerFactoryType {

    func supplyViewControllerForState(_ state: EditorState, context: EditorContext) -> EditableViewController?
}

class MainEditorViewController: PresentableViewController {

    var factory: EditorViewControllerFactoryType!
    var context: EditorContext = EditorContext() {
        didSet {
            let triplet = self.context.configTriplet!
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
            self.title = comps.joined(separator: " + ")
        }
    }

    @IBOutlet weak var containerView: NSView!

    @IBOutlet weak var previousButton: NSButton!
    @IBOutlet weak var nextButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!

    //state and animated?
    private var previousState: (EditorState, Bool) = (.initial, false)
    var state: (EditorState, Bool) = (.initial, false) {
        willSet {
            self.previousState = self.state
        }
        didSet {
            self.previousButton?.isEnabled = self.state.0 != .noServer
            if self.previousState.0 != self.state.0 {
                self.stateChanged(fromState: self.previousState.0, toState: self.state.0, animated: self.state.1)
            }
        }
    }

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
        self.state = (state, false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.containerView.wantsLayer = true
        self.containerView.layer!.backgroundColor = NSColor.lightGray.cgColor

        //HACK: hack for debugging - jump ahead
//        self.state.value = (.EditingSyncer, false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        let size = CGSize(width: 600, height: 422)
        self.view.window?.minSize = size
        self.view.window?.maxSize = size
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
        if let previous = self.state.0.previous() {
            self.state = (previous, animated)
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
        if let next = self.state.0.next() {
            self.state = (next, animated)
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

    //state manipulation

    private func stateChanged(fromState: EditorState, toState: EditorState, animated: Bool) {
        let context = self.context
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
