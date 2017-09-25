//
//  MainEditor_EditeeDelegate.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaKit
import XcodeServerSDK

//here conform to all the delegates of the view controllers and
//figure out what the required actions are.

extension MainEditorViewController: EditeeDelegate { }

extension MainEditorViewController: EmptyXcodeServerViewControllerDelegate {
    
    func didSelectXcodeServerConfig(_ config: XcodeServerConfig) {
        self.context.value.configTriplet.server = config
    }
}

extension MainEditorViewController: XcodeServerViewControllerDelegate {
    
    func didCancelEditingOfXcodeServerConfig(_ config: XcodeServerConfig) {
        self.context.value.configTriplet.server = nil
        self.previous(animated: false)
    }
    
    func didSaveXcodeServerConfig(_ config: XcodeServerConfig) {
        self.context.value.configTriplet.server = config
    }
}

extension MainEditorViewController: EmptyProjectViewControllerDelegate {
    
    func didSelectProjectConfig(_ config: ProjectConfig) {
        self.context.value.configTriplet.project = config
    }
}

extension MainEditorViewController: ProjectViewControllerDelegate {
    
    func didCancelEditingOfProjectConfig(_ config: ProjectConfig) {
        self.context.value.configTriplet.project = nil
        self.previous(animated: false)
    }
    
    func didSaveProjectConfig(_ config: ProjectConfig) {
        self.context.value.configTriplet.project = config
    }
}

extension MainEditorViewController: EmptyBuildTemplateViewControllerDelegate {
    
    func didSelectBuildTemplate(_ buildTemplate: BuildTemplate) {
        self.context.value.configTriplet.buildTemplate = buildTemplate
    }
}

extension MainEditorViewController: BuildTemplateViewControllerDelegate {
    
    func didCancelEditingOfBuildTemplate(_ template: BuildTemplate) {
        self.context.value.configTriplet.buildTemplate = nil
        self.previous(animated: false)
    }
    
    func didSaveBuildTemplate(_ template: BuildTemplate) {
        self.context.value.configTriplet.buildTemplate = template
    }
}

extension MainEditorViewController: SyncerViewControllerDelegate {
    
    func didCancelEditingOfSyncerConfig(_ config: SyncerConfig) {
        self._cancel()
    }
    
    func didSaveSyncerConfig(_ config: SyncerConfig) {
        self.context.value.configTriplet.syncer = config
    }
    
    func didRequestEditing() {
        self.state.value = (.noServer, true)
    }
}

