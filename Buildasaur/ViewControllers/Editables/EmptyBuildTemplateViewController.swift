//
//  EmptyBuildTemplateViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/6/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit
import BuildaUtils
import XcodeServerSDK

protocol EmptyBuildTemplateViewControllerDelegate: class {
    func didSelectBuildTemplate(_ buildTemplate: BuildTemplate)
}

class EmptyBuildTemplateViewController: EditableViewController {

    //for cases when we're editing an existing syncer - show the
    //right preference.
    var existingTemplateId: RefType?

    //for requesting just the right build templates
    var projectName: String!

    weak var emptyTemplateDelegate: EmptyBuildTemplateViewControllerDelegate?

    @IBOutlet weak var existingBuildTemplatesPopup: NSPopUpButton!

    private var buildTemplates: [BuildTemplate] = []
    private var selectedTemplate: BuildTemplate? = nil {
        didSet {
            self.nextAllowed = self.selectedTemplate != nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        precondition(self.projectName != nil)

        self.setupDataSource()
        self.setupPopupAction()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        //select if existing template is being edited
        //TODO: also the actual index in the popup must be selected!
        let index: Int
        if let id = self.selectedTemplate?.id {
            let ids = self.buildTemplates.map { $0.id }
            index = ids.index(of: id) ?? 0
        } else if let configId = self.existingTemplateId {
            let ids = self.buildTemplates.map { $0.id }
            index = ids.index(of: configId) ?? 0
        } else {
            index = 0
        }
        self.selectItemAtIndex(index)
        self.existingBuildTemplatesPopup.selectItem(at: index)
        self.nextAllowed = self.selectedTemplate != nil
    }

    private var addNewString: String {
        return "Add new build template..."
    }

    func newTemplate() -> BuildTemplate {
        return BuildTemplate(projectName: self.projectName)
    }

    override func shouldGoNext() -> Bool {
        self.didSelectBuildTemplate(self.selectedTemplate!)
        return super.shouldGoNext()
    }

    private func selectItemAtIndex(_ index: Int) {

        let templates = self.buildTemplates

        //                                      last item is "add new"
        let template = (index == templates.count) ? self.newTemplate() : templates[index]
        self.selectedTemplate = template
    }

    private func setupPopupAction() {
        self.existingBuildTemplatesPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }
            let index = sself.existingBuildTemplatesPopup.indexOfSelectedItem
            sself.selectItemAtIndex(index)
        }
    }

    private func setupDataSource() {
        let update = { [weak self] in
            guard let sself = self else { return }

            sself.buildTemplates = sself.storageManager.buildTemplatesForProjectName(projectName: sself.projectName).sorted { $0.name < $1.name }
            let popup = sself.existingBuildTemplatesPopup
            popup?.removeAllItems()
            var configDisplayNames = sself.buildTemplates.map { template -> String in
                let project = template.projectName ?? ""
                return "\(template.name) (\(project))"
            }
            configDisplayNames.append(sself.addNewString)
            popup?.addItems(withTitles: configDisplayNames)
        }
        self.storageManager.onUpdateBuildTemplates = update
        update()
    }

    private func didSelectBuildTemplate(_ template: BuildTemplate) {
        Log.verbose("Selected \(template.name)")
        self.emptyTemplateDelegate?.didSelectBuildTemplate(template)
    }
}
