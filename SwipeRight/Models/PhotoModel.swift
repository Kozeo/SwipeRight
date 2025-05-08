import Foundation
import SwiftUI
import Photos

struct PhotoModel: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let image: UIImage?
    let creationDate: Date?
    var swipeDirection: SwipeDirection = .none
    
    // Computed property for a downsized image to use during animations
    var thumbnailImage: UIImage? {
        guard let image = image else { return nil }
        
        // Use the original image directly if it's already small enough
        let maxDimension: CGFloat = 300
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image
        }
        
        // Otherwise, create a thumbnail
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
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