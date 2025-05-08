import Foundation
import Photos
import SwiftUI
import Observation

@Observable final class PhotoViewModel {
    // State
    var photos: [PhotoModel] = []
    var currentIndex: Int = 0
    var permissionGranted: Bool = false
    var isLoading: Bool = false
    var error: String? = nil
    
    // Computed properties
    var currentPhoto: PhotoModel? {
        guard !photos.isEmpty, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }
    
    var hasMorePhotos: Bool {
        return currentIndex < photos.count - 1
    }
    
    // MARK: - Photo Library Access
    
    func requestPhotoLibraryPermission() async {
        isLoading = true
        defer { isLoading = false }
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            permissionGranted = true
            await loadPhotos()
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            permissionGranted = (newStatus == .authorized || newStatus == .limited)
            if permissionGranted {
                await loadPhotos()
            }
        case .denied, .restricted:
            permissionGranted = false
            error = "Photo library access is denied. Please enable it in Settings."
        @unknown default:
            permissionGranted = false
            error = "Unknown permission status."
        }
    }
    
    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }
        
        // Create fetch options for photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        fetchOptions.fetchLimit = 10 // Fetch 10 random photos as requested
        
        // Fetch photos
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        // Create photo models
        var newPhotos: [PhotoModel] = []
        
        // Convert PHAssets to PhotoModels with images
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.deliveryMode = .highQualityFormat
        
        for i in 0..<min(10, assets.count) {
            let asset = assets.object(at: i)
            var image: UIImage?
            
            manager.requestImage(for: asset, 
                                targetSize: CGSize(width: 800, height: 800),
                                contentMode: .aspectFit,
                                options: requestOptions) { result, _ in
                image = result
            }
            
            let photo = PhotoModel(asset: asset, image: image)
            newPhotos.append(photo)
        }
        
        await MainActor.run {
            self.photos = newPhotos
            self.currentIndex = 0
        }
    }
    
    // MARK: - Swipe Actions
    
    func processSwipe(_ direction: SwipeDirection) {
        switch direction {
        case .left:
            // Archive photo - in a real app, this would move the photo to an archive
            print("Photo archived: \(currentPhoto?.id ?? "unknown")")
        case .right:
            // Keep photo
            print("Photo kept: \(currentPhoto?.id ?? "unknown")")
        case .none:
            break
        }
        
        // Move to the next photo if available
        if hasMorePhotos {
            currentIndex += 1
        }
    }
    
    func resetPhotos() async {
        await loadPhotos()
    }
} 