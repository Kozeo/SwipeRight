import Foundation
import Photos
import SwiftUI
import Observation

@Observable final class PhotoViewModel {
    // State
    var photoAssets: [PHAsset] = []
    var currentPhoto: PhotoModel?
    var prefetchedPhotos: [String: UIImage] = [:]
    var currentIndex: Int = 0
    var permissionGranted: Bool = false
    var isLoading: Bool = false
    var isBatchComplete: Bool = false
    var error: String? = nil
    var batchSize: Int = 10
    private var imageRequestIDs: [PHImageRequestID] = []
    
    // Computed properties
    var hasMorePhotos: Bool {
        return currentIndex < photoAssets.count - 1
    }
    
    var progress: String {
        return "\(currentIndex + 1) of \(photoAssets.count)"
    }
    
    // MARK: - Photo Library Access
    
    func requestPhotoLibraryPermission() async {
        isLoading = true
        defer { isLoading = false }
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            permissionGranted = true
            await prepareBatch()
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            permissionGranted = (newStatus == .authorized || newStatus == .limited)
            if permissionGranted {
                await prepareBatch()
            }
        case .denied, .restricted:
            permissionGranted = false
            error = "Photo library access is denied. Please enable it in Settings."
        @unknown default:
            permissionGranted = false
            error = "Unknown permission status."
        }
    }
    
    func prepareBatch() async {
        isLoading = true
        isBatchComplete = false
        currentPhoto = nil
        prefetchedPhotos.removeAll()
        cancelAllImageRequests()
        
        // Create fetch options for photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        // Fetch all photo assets
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
        // Make sure there are photos
        if allAssets.count == 0 {
            await MainActor.run {
                self.isLoading = false
                self.error = "No photos found in your library."
            }
            return
        }
        
        // Select random subset for batch
        let totalCount = allAssets.count
        var selectedIndexes = Set<Int>()
        
        // Make sure we don't try to get more photos than exist
        let actualBatchSize = min(batchSize, totalCount)
        
        // Generate random indices
        while selectedIndexes.count < actualBatchSize {
            let randomIndex = Int.random(in: 0..<totalCount)
            selectedIndexes.insert(randomIndex)
        }
        
        // Get the assets for the selected indices
        var batchAssets: [PHAsset] = []
        for index in selectedIndexes {
            batchAssets.append(allAssets.object(at: index))
        }
        
        // Update state
        await MainActor.run {
            self.photoAssets = batchAssets
            self.currentIndex = 0
            self.isLoading = false
        }
        
        // Load the first photo immediately after updating the state
        await loadCurrentPhoto()
        
        // Prefetch the next few photos
        prefetchNextPhotos()
    }
    
    private func cancelAllImageRequests() {
        let manager = PHImageManager.default()
        for requestID in imageRequestIDs {
            manager.cancelImageRequest(requestID)
        }
        imageRequestIDs.removeAll()
    }
    
    func loadCurrentPhoto() async {
        // Clear the current photo while loading the next one
        await MainActor.run {
            isLoading = true
            currentPhoto = nil
        }
        
        // Check if we've reached the end of the batch
        guard currentIndex < photoAssets.count else {
            await MainActor.run {
                isLoading = false
                isBatchComplete = true
            }
            return
        }
        
        // Get the asset for the current index
        let asset = photoAssets[currentIndex]
        let assetID = asset.localIdentifier
        
        // Check if we already have this image prefetched
        if let prefetchedImage = prefetchedPhotos[assetID] {
            // Create photo model and update state with prefetched image
            let photo = PhotoModel(asset: asset, image: prefetchedImage)
            
            // Update on the main actor
            await MainActor.run {
                currentPhoto = photo
                isLoading = false
                
                // Remove from prefetch cache to save memory
                self.prefetchedPhotos.removeValue(forKey: assetID)
            }
            
            // Prefetch next photos
            prefetchNextPhotos()
            return
        }
        
        // Load the image if not prefetched
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat // Changed from opportunistic to avoid multiple callbacks
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false
        requestOptions.resizeMode = .exact // Get exact size to reduce processing
        
        // Use continuation to properly handle the asynchronous callback
        let image = await withCheckedContinuation { continuation in
            // Track if we've already resumed to prevent double-resuming
            var hasResumed = false
            
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 800, height: 800),
                contentMode: .aspectFit,
                options: requestOptions
            ) { result, info in
                // Only resume once
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }
            // Store request ID for potential cancellation
            imageRequestIDs.append(requestID)
        }
        
        // Create photo model and update state
        let photo = PhotoModel(asset: asset, image: image)
        
        // Update on the main actor
        await MainActor.run {
            currentPhoto = photo
            isLoading = false
        }
        
        // Prefetch next photos
        prefetchNextPhotos()
    }
    
    private func prefetchNextPhotos() {
        // Prefetch next 2 photos if available
        let prefetchCount = 2
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.isNetworkAccessAllowed = true
        
        for offset in 1...prefetchCount {
            let nextIndex = currentIndex + offset
            guard nextIndex < photoAssets.count else { break }
            
            let asset = photoAssets[nextIndex]
            let assetID = asset.localIdentifier
            
            // Skip if already prefetched
            if prefetchedPhotos[assetID] != nil { continue }
            
            // Request lower-res image for prefetching
            let requestID = manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 500, height: 500),
                contentMode: .aspectFit,
                options: requestOptions
            ) { [weak self] image, info in
                guard let self = self, let image = image else { return }
                
                // Store the prefetched image
                Task { @MainActor in
                    self.prefetchedPhotos[assetID] = image
                }
            }
            
            // Store request ID for potential cancellation
            imageRequestIDs.append(requestID)
        }
    }
    
    // MARK: - Swipe Actions
    
    func processSwipe(_ direction: SwipeDirection) async {
        // Process the swipe action
        switch direction {
        case .left:
            // Archive photo logic would go here
            print("Photo archived: \(currentPhoto?.id ?? "unknown")")
        case .right:
            // Keep photo logic would go here
            print("Photo kept: \(currentPhoto?.id ?? "unknown")")
        case .none:
            break
        }
        
        // Immediately clear the current photo to indicate processing
        await MainActor.run {
            currentPhoto = nil
        }
        
        // Move to the next photo
        if hasMorePhotos {
            currentIndex += 1
            await loadCurrentPhoto()
        } else {
            // We've processed all photos in the batch
            await MainActor.run {
                isBatchComplete = true
            }
        }
    }
    
    func startNewBatch() async {
        await MainActor.run {
            isBatchComplete = false
            currentPhoto = nil
            currentIndex = 0
            photoAssets = []
            prefetchedPhotos.removeAll()
        }
        
        cancelAllImageRequests()
        await prepareBatch()
    }
}
