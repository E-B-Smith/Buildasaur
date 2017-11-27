//
//  EditorViewControllerFactory.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/5/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import XcodeServerSDK

enum EditorVCType: String {
    case XcodeServerVC = "xcodeServerViewController"
    case EmptyXcodeServerVC = "emptyXcodeServerViewController"
    case ProjectVC = "projectViewController"
    case EmptyProjectVC = "emptyProjectViewController"
    case BuildTemplateVC = "buildTemplateViewController"
    case EmptyBuildTemplateVC = "emptyBuildTemplateViewController"
    case SyncerStatusVC = "syncerViewController"
}

class EditorViewControllerFactory: EditorViewControllerFactoryType {

    let storyboardLoader: StoryboardLoader
    let serviceAuthenticator: ServiceAuthenticator

    init(storyboardLoader: StoryboardLoader, serviceAuthenticator: ServiceAuthenticator) {
        self.storyboardLoader = storyboardLoader
        self.serviceAuthenticator = serviceAuthenticator
    }

    func supplyViewControllerForState(_ state: EditorState, context: EditorContext) -> EditableViewController? {
        let editableViewController: EditableViewController?
        switch state {
        case .noServer:
            let vc: EmptyXcodeServerViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.EmptyXcodeServerVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.loadView()
            vc.existingConfigId = context.configTriplet.server?.id
            vc.emptyServerDelegate = context.editeeDelegate
            editableViewController = vc

        case .editingServer:
            let vc: XcodeServerViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.XcodeServerVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.loadView()
            vc.serverConfig = context.configTriplet.server!
            vc.delegate = context.editeeDelegate
            editableViewController = vc

        case .noProject:
            let vc: EmptyProjectViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.EmptyProjectVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.loadView()
            vc.existingConfigId = context.configTriplet.project?.id
            vc.emptyProjectDelegate = context.editeeDelegate
            editableViewController = vc

        case .editingProject:
            let vc: ProjectViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.ProjectVC.rawValue)
            vc.loadView()
            vc.syncerManager = context.syncerManager
            vc.projectConfig = context.configTriplet.project!
            vc.delegate = context.editeeDelegate
            vc.serviceAuthenticator = self.serviceAuthenticator
            editableViewController = vc

        case .noBuildTemplate:
            let vc: EmptyBuildTemplateViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.EmptyBuildTemplateVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.existingTemplateId = context.configTriplet.buildTemplate?.id
            vc.projectName = context.configTriplet.project!.name
            vc.existingTemplateId = context.configTriplet.buildTemplate?.id
            vc.emptyTemplateDelegate = context.editeeDelegate
            editableViewController = vc

        case .editingBuildTemplate:
            let vc: BuildTemplateViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.BuildTemplateVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.loadView()
            vc.projectRef = context.configTriplet.project!.id
            vc.xcodeServerRef = context.configTriplet.server!.id
            vc.buildTemplate = context.configTriplet.buildTemplate!
            vc.delegate = context.editeeDelegate
            editableViewController = vc

        case .syncer:
            let vc: SyncerViewController = self.storyboardLoader.typedViewControllerWithStoryboardIdentifier(EditorVCType.SyncerStatusVC.rawValue)
            vc.syncerManager = context.syncerManager
            vc.loadView()

            //ensure the syncer config has the right ids linked up
            let triplet = context.configTriplet!
            var syncerConfig = triplet.syncer
            syncerConfig.xcodeServerRef = triplet.server!.id
            syncerConfig.projectRef = triplet.project!.id
            syncerConfig.preferredTemplateRef = triplet.buildTemplate!.id
            vc.syncerConfig = syncerConfig
            vc.delegate = context.editeeDelegate
            vc.xcodeServerConfig = triplet.server!
            vc.projectConfig = triplet.project!
            vc.buildTemplate = triplet.buildTemplate!
            editableViewController = vc

        case .initial:
             editableViewController = nil
        case .final:
            editableViewController = nil
        }

        return editableViewController
    }
}
