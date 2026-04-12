//
//  Item.swift
//  LiveDashBoardAgent
//
//  Created by Steve5wutongyu6 on 2026/4/12.
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
