//
//  URLUtils.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 10/13/15.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa

func openLink(_ link: String) {
    
    if let url = URL(string: link) {
        NSWorkspace.shared.open(url)
    }
}
