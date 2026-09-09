//
//  Item.swift
//  clipforgeios
//
//  Created by 陈垌铭 on 2026/9/9.
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
