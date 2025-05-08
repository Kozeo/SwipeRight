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
    
    // Static cache for thumbnails
    private static var thumbnailCache: [String: UIImage] = [:]
    
    // Computed property for a downsized image to use during animations
    var thumbnailImage: UIImage? {
        // Use cached thumbnail if available
        if let cachedThumbnail = PhotoModel.thumbnailCache[id] {
            return cachedThumbnail
        }
        
        guard let image = image else { return nil }
        
        // Use the original image directly if it's already small enough
        let maxDimension: CGFloat = 400  // Size for thumbnails
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            PhotoModel.thumbnailCache[id] = image
            return image
        }
        
        // Otherwise, create a thumbnail with optimal performance
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        // Use UIGraphicsImageRenderer for better performance with better quality
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            // Set high quality context
            context.cgContext.interpolationQuality = .high
            
            // Set rendering intent for better colors
            context.cgContext.renderingIntent = .perceptual
            
            // Draw with high quality
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Cache the result
        PhotoModel.thumbnailCache[id] = thumbnail
        
        // Perform cache cleanup if we have too many thumbnails
        cleanupThumbnailCacheIfNeeded()
        
        return thumbnail
    }
    
    // Cache size management
    private func cleanupThumbnailCacheIfNeeded() {
        let maxCacheSize = 30 // Limit cache size to prevent excessive memory usage
        
        if PhotoModel.thumbnailCache.count > maxCacheSize {
            // Remove approximately 1/3 of the cache when limit is exceeded
            let removeCount = PhotoModel.thumbnailCache.count / 3
            
            // Get the first N keys to remove
            let keysToRemove = Array(PhotoModel.thumbnailCache.keys.prefix(removeCount))
            
            // Remove these items from the cache
            for key in keysToRemove {
                PhotoModel.thumbnailCache.removeValue(forKey: key)
            }
        }
    }
    
    // Determines the appropriate resolution image based on card position
    func imageForPosition(isTopCard: Bool) -> UIImage? {
        if isTopCard {
            return image // Always use highest quality for the top card
        } else {
            return thumbnailImage ?? image // Fall back to full image if thumbnail unavailable
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