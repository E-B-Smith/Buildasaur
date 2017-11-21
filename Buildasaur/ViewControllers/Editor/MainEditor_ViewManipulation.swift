//
//  MainEditor_ViewManipulation.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa

extension MainEditorViewController {

    //view controller manipulation

    private func rebindContentViewController() {
        let content = self._contentViewController!

        content.onNextAllowedChanged = { [weak self] nextAllowed in
            self?.nextButton.isEnabled = nextAllowed
        }
        content.onPreviousAllowedChanged = { [weak self] previousAllowed in
            self?.previousButton.isEnabled = previousAllowed
        }
        content.onCancelAllowedChanged = { [weak self] cancelAllowed in
            self?.cancelButton.isEnabled = cancelAllowed
        }
        content.onNextTitleChanged = { [weak self] nextTitle in
            self?.nextButton.title = nextTitle
        }
        content.onWantsNext = { [weak self] animated in
            self?._next(animated: animated)
        }
        content.onWantsPrevious = { [weak self] animated in
            self?._previous(animated: animated)
        }
    }

    private func remove(_ viewController: NSViewController?) {
        guard let vc = viewController else { return }
        vc.view.removeFromSuperview()
        vc.removeFromParentViewController()
    }

    private func add(_ viewController: EditableViewController) {
        self.addChildViewController(viewController)
        let view = viewController.view

        //also match backgrounds?
        view.wantsLayer = true
        view.layer!.backgroundColor = self.containerView.layer!.backgroundColor

        //setup
        self._contentViewController = viewController
        self.rebindContentViewController()

        self.containerView.addSubview(view)
    }

    func setContentViewController(_ viewController: EditableViewController, animated: Bool) {
        //1. remove the old view
        self.remove(self._contentViewController)

        //2. add the new view on top of the old one
        self.add(viewController)

        //if no animation, complete immediately
        if !animated {
            return
        }

        //animation, yay!

        let newView = viewController.view

        //3. offset the new view to the right
        var startingFrame = newView.frame
        let originalFrame = startingFrame
        startingFrame.origin.x += startingFrame.size.width
        newView.frame = startingFrame

        //4. start an animation from right to the center
        NSAnimationContext.runAnimationGroup({ (context: NSAnimationContext) -> Void in
            context.duration = 0.3
            newView.animator().frame = originalFrame
        })
    }
}
