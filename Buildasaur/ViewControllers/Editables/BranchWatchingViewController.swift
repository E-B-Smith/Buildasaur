//
//  BranchWatchingViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 23/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaGitServer
import BuildaUtils
import BuildaKit

protocol BranchWatchingViewControllerDelegate: class {

    func didUpdateWatchedBranches(_ branches: [String])
}

private struct ShowableBranch {
    let name: String
    let pr: Int?
}

class BranchWatchingViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

    //these two must be set before viewDidLoad by its presenting view controller
    var syncer: StandardSyncer!
    var watchedBranchNames: Set<String>!
    weak var delegate: BranchWatchingViewControllerDelegate?

    private var branches: [ShowableBranch] = []

    @IBOutlet weak var branchActivityIndicator: NSProgressIndicator!
    @IBOutlet weak var branchesTableView: NSTableView!

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(self.syncer != nil, "Syncer has not been set")
        self.watchedBranchNames = Set(self.syncer.config.watchedBranchNames)

        self.branchesTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }

    private var _branches: [BranchType]?
    private var _prs: [PullRequestType]?
    override func viewWillAppear() {
        super.viewWillAppear()

        self.branchActivityIndicator.startAnimation(nil)

        let completion = { [weak self] in
            guard let sself = self else { return }
            if let _branches = sself._branches,
                let _prs = sself._prs {
                let mappedPRs = _prs.dictionarifyWithKey { $0.headName }
                sself.branches = _branches.map {
                    let pr = mappedPRs[$0.name]?.number
                    return ShowableBranch(name: $0.name, pr: pr)
                }
                sself.branchesTableView.reloadData()
                sself.branchActivityIndicator.stopAnimation(nil)
            }
        }

        self.fetchBranches { [weak self] (branches, error) in
            if let error = error {
                UIUtils.showAlertWithError(error)
                return
            }
            self?._branches = branches
            completion()
        }

        self.fetchPRs { [weak self] (prs, error) in
            if let error = error {
                UIUtils.showAlertWithError(error)
                return
            }
            self?._prs = prs
            completion()
        }
    }

    func fetchBranches(completion: @escaping ([BranchType], Error?) -> Void) {
        let repoName = self.syncer.project.serviceRepoName()!
        self.syncer.sourceServer.getBranchesOfRepo(repo: repoName) { (branches, error) -> Void in
            if let error = error {
                completion([], error)
            } else {
                completion(branches!, nil)
            }
        }
    }

    func fetchPRs(completion: @escaping ([PullRequestType], Error?) -> Void) {
        let repoName = self.syncer.project.serviceRepoName()!
        self.syncer.sourceServer.getOpenPullRequests(repo: repoName) { (prs, error) -> Void in
            if let error = error {
                completion([], error)
            } else {
                completion(prs!, nil)
            }
        }
    }

    @IBAction func cancelTapped(_ sender: AnyObject) {
        self.dismiss(nil)
    }

    @IBAction func doneTapped(_ sender: AnyObject) {
        let updated = Array(self.watchedBranchNames)
        self.delegate?.didUpdateWatchedBranches(updated)
        self.dismiss(nil)
    }

    // MARK: branches table view

    func numberOfRows(in tableView: NSTableView) -> Int {

        if tableView == self.branchesTableView {
            return self.branches.count
        }
        return 0
    }

    func getTypeOfReusableView<T: NSView>(_ column: String) -> T {
        guard let view = self.branchesTableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: column), owner: self) else {
            fatalError("Couldn't get a reusable view for column \(column)")
        }
        guard let typedView = view as? T else {
            fatalError("Couldn't type view \(view) into type \(T.className())")
        }
        return typedView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        guard let tcolumn = tableColumn else { return nil }
        let columnIdentifier = tcolumn.identifier

        let branch = self.branches[row]

        switch columnIdentifier.rawValue {

        case "name":
            let view: NSTextField = self.getTypeOfReusableView(columnIdentifier.rawValue)
            var name = branch.name
            if let pr = branch.pr {
                name += " (watched as PR #\(pr))"
            }
            view.stringValue = name
            return view
        case "enabled":
            let checkbox: BuildaNSButton = self.getTypeOfReusableView(columnIdentifier.rawValue)
            if branch.pr != nil {
                checkbox.on = true
                checkbox.isEnabled = false
            } else {
                checkbox.on = self.watchedBranchNames.contains(branch.name)
                checkbox.isEnabled = true
            }
            checkbox.row = row
            return checkbox
        default:
            return nil
        }
    }

    @IBAction func branchesTableViewRowCheckboxTapped(_ sender: BuildaNSButton) {

        //toggle selection in model
        let branch = self.branches[sender.row!]
        let branchName = branch.name

        //see if we are checking or unchecking
        let previouslyEnabled = self.watchedBranchNames.contains(branchName)

        if previouslyEnabled {
            //disable
            self.watchedBranchNames.remove(branchName)
        } else {
            //enable
            self.watchedBranchNames.insert(branchName)
        }
    }

}
