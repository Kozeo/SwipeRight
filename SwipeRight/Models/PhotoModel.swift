import Foundation
import SwiftUI
import Photos

struct PhotoModel: Identifiable, Equatable {
    let id: String
    let asset: PHAsset
    let image: UIImage?
    let creationDate: Date?
    var swipeDirection: SwipeDirection = .none
    
    // Stack positioning properties
    var zIndex: Double = 0
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    
    // Optional pre-cached versions at different quality levels
    private var _thumbnailImage: UIImage?
    
    // Computed property for a downsized image to use during animations
    var thumbnailImage: UIImage? {
        // Use cached thumbnail if available
        if let cachedThumbnail = _thumbnailImage {
            return cachedThumbnail
        }
        
        guard let image = image else { return nil }
        
        // Use the original image directly if it's already small enough
        let maxDimension: CGFloat = 300
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            _thumbnailImage = image
            return image
        }
        
        // Otherwise, create a thumbnail with optimal performance
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        // Use UIGraphicsImageRenderer for better performance
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            // Draw with high quality for thumbnail (still much faster than full image)
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Cache the result
        _thumbnailImage = thumbnail
        return thumbnail
    }
    
    // Determines the appropriate resolution image based on card position
    func imageForPosition(isTopCard: Bool) -> UIImage? {
        if isTopCard {
            return image
        } else {
            return thumbnailImage
        }
    }
    
    init(asset: PHAsset, image: UIImage?) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
    }
    
    // Initialize with stack position parameters
    init(asset: PHAsset, image: UIImage?, zIndex: Double = 0, scale: CGFloat = 1.0, offset: CGSize = .zero) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
        self.zIndex = zIndex
        self.scale = scale
        self.offset = offset
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