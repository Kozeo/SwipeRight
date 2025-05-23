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
    
    // Stack management
    var visiblePhotoStack: [PhotoModel] = []
    let maxStackSize: Int = 3
    var isPreparingStack: Bool = false
    
    // State transition tracking
    private(set) var transitionState: TransitionState = .idle
    
    // Memory management
    private let maxPrefetchedPhotos: Int = 5
    private var processingAssetIDs: Set<String> = []
    private var lastAccessTime: [String: Date] = [:]
    private var currentlyVisibleIDs: Set<String> = [] // Track currently visible assets for better caching
    
    // Cache for different image resolutions
    private var highQualityCache: [String: UIImage] = [:]
    private var mediumQualityCache: [String: UIImage] = [:]
    private var thumbnailCache: [String: UIImage] = [:]
    private let cacheSizeLimit: Int = 15 // Overall image cache size limit
    
    // Image size constants - increased for better quality
    private let highQualitySize: CGSize = CGSize(width: 2400, height: 2400)  // Increased for better quality
    private let mediumQualitySize: CGSize = CGSize(width: 1500, height: 1500) 
    private let thumbnailSize: CGSize = CGSize(width: 600, height: 600)
    
    // Computed properties
    var hasMorePhotos: Bool {
        return currentIndex < photoAssets.count - 1
    }
    
    var progress: String {
        if photoAssets.isEmpty {
            return "No photos"
        }
        return "\(currentIndex + 1) of \(photoAssets.count)"
    }
    
    var isLastPhoto: Bool {
        return currentIndex == photoAssets.count - 1
    }
    
    var isFirstPhoto: Bool {
        return currentIndex == 0
    }
    
    var remainingPhotoCount: Int {
        return max(0, photoAssets.count - currentIndex - 1)
    }
    
    // MARK: - Photo Library Access
    
    func requestPhotoLibraryPermission() async {
        transitionTo(.loading("Checking permissions"))
        
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
            } else {
                transitionTo(.error("Photo library access denied"))
            }
        case .denied, .restricted:
            permissionGranted = false
            transitionTo(.error("Photo library access is denied. Please enable it in Settings."))
        @unknown default:
            permissionGranted = false
            transitionTo(.error("Unknown permission status."))
        }
    }
    
    func prepareBatch() async {
        transitionTo(.loading("Preparing photos"))
        
        // Clear resources but keep visible stack temporarily
        clearAllCachedResources(preserveStack: true)
        
        // Create fetch options for photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        
        // Fetch all photo assets
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
        // Make sure there are photos
        if allAssets.count == 0 {
            await MainActor.run {
                visiblePhotoStack.removeAll() // Now clear the stack
                self.transitionTo(.noPhotos)
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
        
        // Get the assets for the selected indices - make a local copy for capturing
        var localBatchAssets: [PHAsset] = []
        for index in selectedIndexes {
            localBatchAssets.append(allAssets.object(at: index))
        }
        
        // Update state
        await MainActor.run {
            self.photoAssets = localBatchAssets
            self.currentIndex = 0
            
            // Now clear the previous stack since we have new content ready
            visiblePhotoStack.removeAll()
        }
        
        // Load the initial photo stack
        await prepareInitialStack()
        
        // Prefetch the next few photos
        prefetchNextPhotos()
        
        // Transition to viewing state
        if visiblePhotoStack.isEmpty {
            transitionTo(.noPhotos)
        } else {
            transitionTo(.idle)
        }
    }
    
    private func transitionTo(_ newState: TransitionState) {
        Task { @MainActor in
            // Handle special cases
            switch newState {
            case .loading:
                isLoading = true
                error = nil
                isBatchComplete = false
            case .idle:
                isLoading = false
                error = nil
            case .error(let message):
                isLoading = false
                error = message
            case .batchComplete:
                isLoading = false
                isBatchComplete = true
                error = nil
            case .noPhotos:
                isLoading = false
                error = "No photos found in your library."
            case .transitioning:
                isLoading = true
                error = nil
                isBatchComplete = false
            case .lastPhoto:
                isLoading = false
                error = nil
                // We're at the last photo but not yet complete
                isBatchComplete = false
            }
            
            // Update transition state
            transitionState = newState
        }
    }
    
    private func clearAllCachedResources(preserveStack: Bool = false) {
        // Cancel all pending image requests
        cancelAllImageRequests()
        
        // Clear all cached images
        prefetchedPhotos.removeAll()
        highQualityCache.removeAll()
        mediumQualityCache.removeAll()
        thumbnailCache.removeAll()
        processingAssetIDs.removeAll()
        lastAccessTime.removeAll()
        currentlyVisibleIDs.removeAll()
        
        // Optionally preserve stack to prevent flickering during transitions
        if !preserveStack {
            visiblePhotoStack.removeAll()
        }
    }
    
    private func cancelAllImageRequests() {
        let manager = PHImageManager.default()
        for requestID in imageRequestIDs {
            manager.cancelImageRequest(requestID)
        }
        imageRequestIDs.removeAll()
    }
    
    // Update the stack after a swipe
    private func updateStackAfterSwipe() async {
        // First set the transition state
        transitionTo(.transitioning)
        
        // Prepare a new photo for the bottom of the stack
        let newStackIndex = currentIndex + maxStackSize - 1
        var newCard: PhotoModel? = nil
        
        // Preload the new card if it exists
        if newStackIndex < photoAssets.count {
            if let newPhoto = await loadPhoto(at: newStackIndex) {
                newCard = PhotoModel(
                    asset: newPhoto.asset,
                    image: newPhoto.image
                )
            }
        }
        
        // Signal that we're preparing the stack to prevent animations
        await MainActor.run {
            isPreparingStack = true
        }
        
        // Short delay to ensure UI updates can process the flag
        try? await Task.sleep(for: .milliseconds(10))
        
        // Update the stack on the main thread
        await MainActor.run {
            // Safety check - ensure stack isn't empty
            guard !visiblePhotoStack.isEmpty else {
                isPreparingStack = false
                return
            }
            
            // Simply remove the first card and keep the rest
            var newStack = Array(visiblePhotoStack.dropFirst())
            
            // If we have a new card to add, append it to the end
            if let card = newCard {
                newStack.append(card)
            }
            
            // Set the current photo to the new top card
            if let newTopCard = newStack.first {
                currentPhoto = newTopCard
            } else {
                currentPhoto = nil
            }
            
            // Replace the entire stack at once
            visiblePhotoStack = newStack
            
            // Update visible IDs
            currentlyVisibleIDs = Set(visiblePhotoStack.map { $0.id })
            
            // Release the preparation flag after a short delay
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                isPreparingStack = false
            }
        }
        
        // Final cleanup and state updates
        cleanupUnusedImages()
        
        // Give a moment for things to settle, then return to idle state
        try? await Task.sleep(for: .milliseconds(100))
        transitionTo(.idle)
    }
    
    // Prepares the initial stack of photos with a simplified approach
    private func prepareInitialStack() async {
        isPreparingStack = true
        
        // Show loading state
        transitionTo(.loading("Loading photos"))
        
        // Create a new stack array
        var newStack: [PhotoModel] = []
        
        // Load photos for the initial stack
        for i in 0..<min(maxStackSize, photoAssets.count - currentIndex) {
            let index = currentIndex + i
            if let photo = await loadPhoto(at: index) {
                newStack.append(photo)
            }
        }
        
        // Update the UI
        await MainActor.run {
            visiblePhotoStack = newStack
            
            if let topPhoto = newStack.first {
                currentPhoto = topPhoto
            }
            
            // Update visible IDs
            currentlyVisibleIDs = Set(visiblePhotoStack.map { $0.id })
            isPreparingStack = false
        }
        
        // Clean up and prefetch
        cleanupUnusedImages()
        prefetchNextPhotos()
        
        // Update state
        if visiblePhotoStack.isEmpty {
            transitionTo(.noPhotos)
        } else {
            transitionTo(.idle)
        }
    }
    
    // Loads a photo at the specified index
    private func loadPhoto(at index: Int) async -> PhotoModel? {
        guard index < photoAssets.count else { return nil }
        
        let asset = photoAssets[index]
        let assetID = asset.localIdentifier
        
        // Update access time for this asset
        updateAccessTime(for: assetID)
        
        // Track this asset as currently visible
        await MainActor.run {
            currentlyVisibleIDs.insert(assetID)
        }
        
        // Determine appropriate quality level based on position in stack
        let isTopCard = index == currentIndex
        let isBackgroundCard = !isTopCard
        let targetSize = isTopCard ? highQualitySize : mediumQualitySize
        
        // Check if we already have this image in the appropriate cache
        if isTopCard, let image = highQualityCache[assetID] {
            return PhotoModel(asset: asset, image: image)
        } else if isBackgroundCard, let image = mediumQualityCache[assetID] {
            return PhotoModel(asset: asset, image: image)
        } else if let image = thumbnailCache[assetID] {
            // Use thumbnail temporarily while we load the appropriate resolution
            let photo = PhotoModel(asset: asset, image: image)
            
            // Asynchronously load the higher quality version if needed
            if isTopCard && highQualityCache[assetID] == nil {
                Task {
                    _ = await loadImageForAsset(asset, targetSize: highQualitySize, forCache: .high)
                }
            } else if isBackgroundCard && mediumQualityCache[assetID] == nil {
                Task {
                    _ = await loadImageForAsset(asset, targetSize: mediumQualitySize, forCache: .medium)
                }
            }
            
            return photo
        }
        
        // Avoid multiple simultaneous requests for the same asset
        guard !processingAssetIDs.contains(assetID) else {
            // Wait a bit and retry if this asset is already being processed
            try? await Task.sleep(for: .milliseconds(100))
            return await loadPhoto(at: index)
        }
        
        // Mark this asset as being processed
        processingAssetIDs.insert(assetID)
        
        // Load image at appropriate quality
        let image = await loadImageForAsset(asset, targetSize: targetSize, forCache: isTopCard ? .high : .medium)
        
        // Mark this asset as no longer being processed
        processingAssetIDs.remove(assetID)
        
        return PhotoModel(asset: asset, image: image)
    }
    
    // Helper enum to specify which cache to use
    private enum CacheType {
        case high, medium, thumbnail
    }
    
    // Load an image for a specific asset with optimal quality
    private func loadImageForAsset(_ asset: PHAsset, targetSize: CGSize, forCache cacheType: CacheType) async -> UIImage? {
        let assetID = asset.localIdentifier
        
        // Load the image with the appropriate quality
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        
        // Configure options based on cache type
        switch cacheType {
        case .high:
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.resizeMode = .exact
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false
            requestOptions.version = .current
        case .medium:
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.resizeMode = .exact
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false
        case .thumbnail:
            requestOptions.deliveryMode = .fastFormat
            requestOptions.resizeMode = .fast
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false
        }
        
        // Use continuation to properly handle the asynchronous callback
        let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            // Track if we've already resumed to prevent double-resuming
            var hasResumed = false
            
            let requestID = manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { result, info in
                // Only resume once
                guard !hasResumed else { return }
                hasResumed = true
                
                // Store the result in our cache if it's valid
                if let image = result {
                    Task { @MainActor in
                        // Store in the appropriate cache
                        switch cacheType {
                        case .high:
                            self.highQualityCache[assetID] = image
                        case .medium:
                            self.mediumQualityCache[assetID] = image
                        case .thumbnail:
                            self.thumbnailCache[assetID] = image
                        }
                        
                        // Also store in prefetchedPhotos for backward compatibility
                        if cacheType == .high {
                            self.prefetchedPhotos[assetID] = image
                        }
                        
                        // Check if we need to clean up
                        self.cleanupCachesIfNeeded()
                    }
                }
                
                continuation.resume(returning: result)
            }
            
            // Store request ID for potential cancellation
            imageRequestIDs.append(requestID)
        }
        
        return image
    }
    
    // Track when assets were last accessed
    private func updateAccessTime(for assetID: String) {
        Task { @MainActor in
            lastAccessTime[assetID] = Date()
        }
    }
    
    // Clean up caches if they exceed the maximum size
    private func cleanupCachesIfNeeded() {
        let totalCacheSize = highQualityCache.count + mediumQualityCache.count + thumbnailCache.count
        
        guard totalCacheSize > cacheSizeLimit else { return }
        
        // Clean up based on Least Recently Used (LRU) policy
        cleanupUnusedImages()
    }
    
    // Clean up images no longer in the visible stack or needed for prefetching
    private func cleanupUnusedImages() {
        Task { @MainActor in
            // Get the current visible asset IDs
            let visibleIDs = Set(visiblePhotoStack.map { $0.id })
            
            // Get IDs of assets that should be prefetched (next few photos)
            var prefetchIDs = Set<String>()
            for i in 0..<maxPrefetchedPhotos {
                let prefetchIndex = currentIndex + maxStackSize + i
                guard prefetchIndex < photoAssets.count else { break }
                prefetchIDs.insert(photoAssets[prefetchIndex].localIdentifier)
            }
            
            // Combined set of assets to keep
            let assetsToKeep = visibleIDs.union(prefetchIDs).union(currentlyVisibleIDs)
            
            // Sort cached images by last access time (oldest first)
            let sortedCachedAssets = lastAccessTime.sorted { $0.value < $1.value }
            
            // Step 1: Remove thumbnails for assets not in keep set
            for (assetID, _) in sortedCachedAssets {
                if !assetsToKeep.contains(assetID) && thumbnailCache[assetID] != nil {
                    thumbnailCache.removeValue(forKey: assetID)
                    
                    // If now we're under the limit, we can stop
                    let totalCacheSize = highQualityCache.count + mediumQualityCache.count + thumbnailCache.count
                    if totalCacheSize <= cacheSizeLimit {
                        break
                    }
                }
            }
            
            // Step 2: If still over limit, remove medium quality images
            if highQualityCache.count + mediumQualityCache.count + thumbnailCache.count > cacheSizeLimit {
                for (assetID, _) in sortedCachedAssets {
                    if !visibleIDs.contains(assetID) && mediumQualityCache[assetID] != nil {
                        mediumQualityCache.removeValue(forKey: assetID)
                        
                        // If now we're under the limit, we can stop
                        let totalCacheSize = highQualityCache.count + mediumQualityCache.count + thumbnailCache.count
                        if totalCacheSize <= cacheSizeLimit {
                            break
                        }
                    }
                }
            }
            
            // Step 3: If still over limit, remove high quality images
            if highQualityCache.count + mediumQualityCache.count + thumbnailCache.count > cacheSizeLimit {
                for (assetID, _) in sortedCachedAssets {
                    if !visibleIDs.contains(assetID) && highQualityCache[assetID] != nil {
                        highQualityCache.removeValue(forKey: assetID)
                        
                        // Also remove from prefetchedPhotos for compatibility
                        prefetchedPhotos.removeValue(forKey: assetID)
                        
                        // If now we're under the limit, we can stop
                        let totalCacheSize = highQualityCache.count + mediumQualityCache.count + thumbnailCache.count
                        if totalCacheSize <= cacheSizeLimit {
                            break
                        }
                    }
                }
            }
            
            // Clean up outdated access times
            for (assetID, _) in lastAccessTime where 
                highQualityCache[assetID] == nil && 
                mediumQualityCache[assetID] == nil && 
                thumbnailCache[assetID] == nil {
                lastAccessTime.removeValue(forKey: assetID)
            }
        }
    }
    
    // Prefetch photos beyond the visible stack
    private func prefetchNextPhotos() {
        // Calculate start index for prefetching (beyond the current stack)
        let startPrefetchIndex = currentIndex + maxStackSize
        let prefetchCount = maxPrefetchedPhotos // Number of photos to prefetch beyond the stack
        let manager = PHImageManager.default()
        
        for offset in 0..<prefetchCount {
            let nextIndex = startPrefetchIndex + offset
            guard nextIndex < photoAssets.count else { break }
            
            let asset = photoAssets[nextIndex]
            let assetID = asset.localIdentifier
            
            // Skip if already prefetched or being processed
            if thumbnailCache[assetID] != nil || processingAssetIDs.contains(assetID) {
                continue
            }
            
            // For prefetching, we'll start with thumbnails
            // This helps to quickly populate the UI when needed
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .fastFormat
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.resizeMode = .fast
            
            // Mark this asset as being processed
            processingAssetIDs.insert(assetID)
            
            // First load thumbnails for fast initial display
            let requestID = manager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,  // Changed to match our other implementation
                options: requestOptions
            ) { [weak self] image, info in
                guard let self = self, let image = image else { 
                    // Mark as no longer processing if we failed
                    Task { @MainActor in
                        self?.processingAssetIDs.remove(assetID)
                    }
                    return 
                }
                
                // Store the thumbnail
                Task { @MainActor in
                    self.thumbnailCache[assetID] = image
                    self.lastAccessTime[assetID] = Date()
                    
                    // Clean up if we're exceeding our limit
                    self.cleanupCachesIfNeeded()
                    
                    // For the immediate next card, also prefetch medium quality
                    if offset == 0 {
                        // Use Task detached to not block main thread
                        Task.detached { [weak self] in
                            guard let self = self else { return }
                            _ = await self.loadImageForAsset(asset, targetSize: self.mediumQualitySize, forCache: .medium)
                        }
                    }
                    
                    // Mark as no longer processing
                    self.processingAssetIDs.remove(assetID)
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
        
        // Move to the next photo if available
        if hasMorePhotos {
            // Transition to loading state but don't clear the visible stack yet
            transitionTo(.transitioning)
            currentIndex += 1
            
            // Special case for approaching the end
            if isLastPhoto {
                transitionTo(.lastPhoto)
            } else {
                transitionTo(.transitioning)
            }
            
            // Update the stack with new positions
            // This is the critical UI update
            isPreparingStack = true
            await updateStackAfterSwipe()
            isPreparingStack = false
            
            // Prefetch more photos beyond the visible stack
            // Do this after stack update to prevent UI jank
            Task {
                prefetchNextPhotos()
                cleanupUnusedImages()
                
                // Return to idle state when done with background tasks
                transitionTo(.idle)
            }
        } else {
            // We've processed all photos in the batch
            // First ensure we're in a transitioning state
            transitionTo(.transitioning)
            
            // Clear internal state carefully to avoid race conditions
            await MainActor.run {
                // Clear stack and reset state
                visiblePhotoStack.removeAll()
                currentPhoto = nil
                processingAssetIDs.removeAll()
                
                // Now transition to batch complete
                transitionTo(.batchComplete)
            }
            
            // Final cleanup to free memory
            Task {
                clearAllCachedResources()
            }
        }
    }
    
    func startNewBatch() async {
        // First, clear all existing state to ensure we start fresh
        transitionTo(.loading("Starting new batch"))
        
        // Clear all in-memory state first
        await MainActor.run {
            isPreparingStack = true
            isBatchComplete = false
            currentPhoto = nil
            currentIndex = 0
            visiblePhotoStack.removeAll()
            photoAssets = []
            processingAssetIDs.removeAll()
            currentlyVisibleIDs.removeAll()
        }
        
        // Cancel any pending image requests
        cancelAllImageRequests()
        
        // Clear all cached resources
        clearAllCachedResources()
        
        // Wait a moment to ensure UI state is stable
        try? await Task.sleep(for: .milliseconds(100))
        
        // Now prepare the new batch
        await prepareBatch()
        
        // Final state check to ensure we're in a valid state
        await MainActor.run {
            isPreparingStack = false
            
            // If we still don't have photos after trying to prepare a batch,
            // make sure we're in the proper state
            if visiblePhotoStack.isEmpty {
                if photoAssets.isEmpty {
                    transitionTo(.noPhotos)
                } else {
                    // Try one more time to load at least one photo
                    Task {
                        await prepareInitialStack()
                    }
                }
            }
        }
    }
}

// MARK: - Transition State Enum
extension PhotoViewModel {
    enum TransitionState: Equatable {
        case idle
        case loading(String)
        case transitioning
        case batchComplete
        case error(String)
        case noPhotos
        case lastPhoto
        
        static func ==(lhs: TransitionState, rhs: TransitionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.loading(let lhsMessage), .loading(let rhsMessage)):
                return lhsMessage == rhsMessage
            case (.transitioning, .transitioning):
                return true
            case (.batchComplete, .batchComplete):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            case (.noPhotos, .noPhotos):
                return true
            case (.lastPhoto, .lastPhoto):
                return true
            default:
                return false
            }
        }
    }
}

// Add safe array access extension - using fileprivate to avoid conflicts
fileprivate extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
