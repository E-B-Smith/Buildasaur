//
//  SourceServerExtensions.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 14/12/2014.
//  Copyright (c) 2014 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

//functions to make working with github easier - utility functions
extension SourceServerType {
    
    /**
    *   Get the latest status of a pull request.
    */
    func getStatusOfPullRequest(pullRequestNumber: Int, repo: String, completion: @escaping (_ status: StatusType?, _ error: Error?) -> ()) {
        
        self.getPullRequest(pullRequestNumber: pullRequestNumber, repo: repo) { (pr, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let pr = pr {
                //fetched PR, now take its head's sha - that's the commit we care about.
                let sha = pr.headName
                self.getStatusOfCommit(commit: sha, repo: repo, completion: completion)
            } else {
                completion(nil, GithubServerError.with("PR is nil and error is nil"))
            }
        }
    }

    //TODO: support paging through all the comments. currently we only fetch the last ~30 comments.
    public func findMatchingCommentInIssue(commentsToMatch: [String], issue: Int, repo: String, completion: @escaping (_ foundComments: [CommentType]?, _ error: Error?) -> ()) {
        
        self.getCommentsOfIssue(issueNumber: issue, repo: repo) { (comments, error) -> () in
            
            if error != nil {
                completion(nil, error)
                return
            }
            
            if let comments = comments {
                let filtered = comments.filter { (comment: CommentType) -> Bool in
                    
                    let filteredSearch = commentsToMatch.filter {
                        (searchString: String) -> Bool in
                        if searchString == comment.body {
                            return true
                        }
                        return false
                    }
                    return filteredSearch.count > 0
                }
                completion(filtered, nil)
            } else {
                completion(nil, GithubServerError.with("Nil comments and nil error. Wat?"))
            }
        }
    }

}
