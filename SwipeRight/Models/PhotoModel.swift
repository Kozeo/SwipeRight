import Foundation
import SwiftUI
import Photos

struct PhotoModel: Identifiable {
    let id: String
    let asset: PHAsset
    let image: UIImage?
    let creationDate: Date?
    
    init(asset: PHAsset, image: UIImage?) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
    }
}

// Enum to represent swipe actions
enum SwipeDirection {
    case left // ARCHIVE
    case right // KEEP
    case none
} 