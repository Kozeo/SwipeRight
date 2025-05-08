import Foundation
import Photos
import SwiftUI
import Observation

@Observable final class PhotoViewModel {
    // State
    var photoAssets: [PHAsset] = []
    var currentPhoto: PhotoModel?
    var currentIndex: Int = 0
    var permissionGranted: Bool = false
    var isLoading: Bool = false
    var isBatchComplete: Bool = false
    var error: String? = nil
    var batchSize: Int = 10
    
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
        
        // Create fetch options for photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        // Fetch all photo assets
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
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
            
            // Load the first photo
            Task {
                await self.loadCurrentPhoto()
            }
        }
    }
    
    func loadCurrentPhoto() async {
        guard currentIndex < photoAssets.count else {
            await MainActor.run {
                currentPhoto = nil
                isBatchComplete = true
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Get the asset for the current index
        let asset = photoAssets[currentIndex]
        
        // Load the image
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false
        
        // Use continuation to properly handle the asynchronous callback
        let image = await withCheckedContinuation { continuation in
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 800, height: 800),
                contentMode: .aspectFit,
                options: requestOptions
            ) { result, info in
                continuation.resume(returning: result)
            }
        }
        
        // Create photo model and update state
        let photo = PhotoModel(asset: asset, image: image)
        
        await MainActor.run {
            currentPhoto = photo
            isLoading = false
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
        
        // Move to the next photo
        if hasMorePhotos {
            currentIndex += 1
            await loadCurrentPhoto()
        } else {
            // We've processed all photos in the batch
            await MainActor.run {
                isBatchComplete = true
                currentPhoto = nil
            }
        }
    }
    
    func startNewBatch() async {
        isBatchComplete = false
        currentPhoto = nil
        currentIndex = 0
        photoAssets = []
        
        await prepareBatch()
    }
} 