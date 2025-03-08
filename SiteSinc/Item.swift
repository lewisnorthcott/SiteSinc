//
//  Item.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
