import Foundation
import SwiftUI
import Photos

struct PhotoModel: Identifiable, Equatable {
    // MARK: - Properties
    let id: String
    let asset: PHAsset
    let image: UIImage?
    let creationDate: Date?
    var swipeDirection: SwipeDirection = .none
    
    // Stack positioning properties
    var zIndex: Double = 0
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    
    // MARK: - Private Cache
    private static var thumbnailCache: [String: UIImage] = [:]
    private static let maxCacheSize = 30
    
    // MARK: - Computed Properties
    
    /// Downsized image to use during animations
    var thumbnailImage: UIImage? {
        // Use cached thumbnail if available
        if let cachedThumbnail = PhotoModel.thumbnailCache[id] {
            return cachedThumbnail
        }
        
        guard let image = image else { return nil }
        
        // Create and cache thumbnail
        let thumbnail = createThumbnail(from: image)
        return thumbnail
    }
    
    // MARK: - Public Methods
    
    /// Determines the appropriate resolution image based on card position
    func imageForPosition(isTopCard: Bool) -> UIImage? {
        if isTopCard {
            return image // Always use highest quality for the top card
        } else {
            return thumbnailImage ?? image // Fall back to full image if thumbnail unavailable
        }
    }
    
    // MARK: - Private Methods
    
    /// Creates a thumbnail from the original image
    private func createThumbnail(from image: UIImage) -> UIImage? {
        let maxDimension: CGFloat = 400  // Size for thumbnails
        
        // Use the original image directly if it's already small enough
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            PhotoModel.thumbnailCache[id] = image
            return image
        }
        
        // Calculate the scale to maintain aspect ratio
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        // Use UIGraphicsImageRenderer for better performance
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { context in
            // Set high quality context
            context.cgContext.interpolationQuality = .high
            
            // Draw with high quality
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Cache the result
        PhotoModel.thumbnailCache[id] = thumbnail
        
        // Perform cache cleanup if we have too many thumbnails
        cleanupThumbnailCacheIfNeeded()
        
        return thumbnail
    }
    
    /// Cache size management
    private func cleanupThumbnailCacheIfNeeded() {
        if PhotoModel.thumbnailCache.count > PhotoModel.maxCacheSize {
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
    
    // MARK: - Initializers
    
    init(asset: PHAsset, image: UIImage?) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
    }
    
    init(asset: PHAsset, image: UIImage?, zIndex: Double = 0, scale: CGFloat = 1.0, offset: CGSize = .zero) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.creationDate = asset.creationDate
        self.zIndex = zIndex
        self.scale = scale
        self.offset = offset
    }
    
    // MARK: - Equatable
    static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SwipeDirection Enum
enum SwipeDirection {
    case left // ARCHIVE
    case right // KEEP
    case none
}