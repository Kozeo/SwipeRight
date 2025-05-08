import Foundation
import SwiftUI
import Photos

struct PhotoModel: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let image: UIImage?
    let creationDate: Date?
    var swipeDirection: SwipeDirection = .none
    
    init(asset: PHAsset, image: UIImage?) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
    }
    
    static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        return lhs.id == rhs.id
    }
}

// Enum to represent swipe actions
enum SwipeDirection {
    case left // ARCHIVE
    case right // KEEP
    case none
} 