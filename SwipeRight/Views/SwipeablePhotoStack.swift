import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    let model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var cardRotation: Double = 0
    @State private var isAnimating: Bool = false
    @State private var currentCardID: String = ""
    @State private var nextCardPreview: UIImage? = nil
    
    // Constants
    private let swipeThreshold: CGFloat = 100.0
    private let rotationFactor: Double = 35.0
    private let swipeAnimationDuration: Double = 0.3
    
    var body: some View {
        GeometryReader { geometry in
            if model.isLoading {
                loadingView
            } else if let currentPhoto = model.currentPhoto {
                photoStackView(geometry: geometry, currentPhoto: currentPhoto)
                    .onAppear {
                        // Store the current card ID to help prevent ghosting
                        currentCardID = currentPhoto.id
                        
                        // Load preview of next photo if available
                        loadNextPhotoPreview()
                    }
            } else if model.isBatchComplete {
                batchCompleteView(geometry: geometry)
            } else if let error = model.error {
                errorView(geometry: geometry, errorMessage: error)
            } else {
                noPhotosView(geometry: geometry)
            }
        }
        // No animation set on currentPhoto to avoid ghosting
        .animation(.easeInOut(duration: 0.3), value: model.isLoading)
        .animation(.easeInOut(duration: 0.3), value: model.isBatchComplete)
    }
    
    // Load next photo preview
    private func loadNextPhotoPreview() {
        // Clear any existing preview
        nextCardPreview = nil
        
        // Check if there's a next photo to preview
        guard model.hasMorePhotos, 
              model.currentIndex + 1 < model.photoAssets.count else {
            return
        }
        
        // Get the next asset
        let nextAssetID = model.photoAssets[model.currentIndex + 1].localIdentifier
        
        // Check if we already have this image prefetched
        if let prefetchedImage = model.prefetchedPhotos[nextAssetID] {
            nextCardPreview = prefetchedImage
        } else {
            // Load a low-res version of the next photo 
            let nextAsset = model.photoAssets[model.currentIndex + 1]
            let manager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .fastFormat
            requestOptions.isNetworkAccessAllowed = true
            
            // Request the image - store in a local variable to capture the preview
            let previewTask = Task { @MainActor in
                // Request the image using the global actor for UI updates
                manager.requestImage(
                    for: nextAsset,
                    targetSize: CGSize(width: 300, height: 300),
                    contentMode: .aspectFit,
                    options: requestOptions
                ) { result, info in
                    guard let image = result else { return }
                    
                    // Update the preview image on the main thread
                    Task { @MainActor in
                        nextCardPreview = image
                    }
                }
            }
            
            // Keep a reference to the task to avoid it being cancelled prematurely
            _ = previewTask
        }
    }
    
    // MARK: - Component Views
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding()
            
            Text("Loading photos...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
    
    private func photoStackView(geometry: GeometryProxy, currentPhoto: PhotoModel) -> some View {
        ZStack {
            // Next photo preview - visible when dragging
            if let nextImage = nextCardPreview, model.hasMorePhotos, abs(dragState.width) > 10 {
                // Calculate opacity based on drag distance
                let dragOpacity = min(abs(Double(dragState.width) / 200), 0.8)
                
                VStack {
                    if let nextCreationDate = model.photoAssets[model.currentIndex + 1].creationDate {
                        Text(dateFormatter.string(from: nextCreationDate))
                            .font(.headline)
                            .padding(.top)
                    }
                    
                    Image(uiImage: nextImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(10)
                        .padding()
                        .frame(maxWidth: geometry.size.width * 0.85, maxHeight: geometry.size.height * 0.7)
                }
                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.85)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.white)
                )
                .shadow(color: Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
                .opacity(dragOpacity) // Dynamic opacity based on drag
                .zIndex(0)
            } else if model.hasMorePhotos {
                // Static placeholder when not dragging or next image not loaded yet
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * 0.85, height: geometry.size.height * 0.8)
                    .cornerRadius(15)
                    .shadow(color: Color.gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    .offset(y: 5)
                    .zIndex(0)
            }
            
            // Show current photo - with key ID to prevent view reuse
            PhotoCardView(
                photo: currentPhoto,
                size: geometry.size,
                dragOffset: dragState,
                onSwiped: { _ in }, // This is handled by the gesture below
                isTopCard: true
            )
            .id(currentCardID) // Use our stored ID to ensure proper identification
            .offset(x: dragState.width, y: dragState.height)
            .rotationEffect(.degrees(Double(dragState.width) / rotationFactor))
            .zIndex(1)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if !isAnimating {
                            self.dragState = gesture.translation
                            self.cardRotation = Double(gesture.translation.width) / rotationFactor
                        }
                    }
                    .onEnded { _ in
                        if !isAnimating && abs(self.dragState.width) > swipeThreshold {
                            let swipeDirection: SwipeDirection = self.dragState.width > 0 ? .right : .left
                            
                            // Set animating flag
                            isAnimating = true
                            
                            // Animate the card off screen
                            withAnimation(.easeOut(duration: swipeAnimationDuration)) {
                                self.dragState.width = self.dragState.width > 0 ? 1000 : -1000
                                self.dragState.height = 100
                            }
                            
                            // Process the swipe after animation
                            Task {
                                // Wait for the animation to complete
                                try? await Task.sleep(for: .milliseconds(300))
                                
                                // Clear current photo immediately
                                await MainActor.run {
                                    // Set dragState to zero before the processSwipe changes the model
                                    self.dragState = .zero
                                }
                                
                                // Process the swipe which will load the next photo
                                await model.processSwipe(swipeDirection)
                                
                                // Reset animation flag after a brief delay to ensure clean transition
                                try? await Task.sleep(for: .milliseconds(100))
                                await MainActor.run {
                                    self.isAnimating = false
                                }
                            }
                        } else if !isAnimating {
                            // Reset if not swiped enough
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                self.dragState = .zero
                                self.cardRotation = 0
                            }
                        }
                    }
            )
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8).combined(with: .offset(y: 20))),
                    removal: .opacity.combined(with: .offset(x: 0, y: 0))
                )
            )
        }
        .padding()
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func batchCompleteView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .padding()
            
            Text("Batch Complete!")
                .font(.title)
                .bold()
            
            Text("You've processed all photos in this batch.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Start New Batch") {
                Task {
                    await model.startNewBatch()
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.top)
        }
        .transition(.opacity.combined(with: .scale))
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func errorView(geometry: GeometryProxy, errorMessage: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
                .padding()
            
            Text(errorMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding()
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func noPhotosView(geometry: GeometryProxy) -> some View {
        VStack {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.gray)
                .padding()
            
            Text("No photos available")
                .font(.headline)
                .padding()
            
            Button("Refresh") {
                Task {
                    await model.startNewBatch()
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    // Date formatter for displaying photo dates
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

// Preview provider
#Preview {
    SwipeablePhotoStack(model: PhotoViewModel())
} 