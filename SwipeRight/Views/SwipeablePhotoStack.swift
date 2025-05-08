import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    let model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var cardRotation: Double = 0
    @State private var isAnimating: Bool = false
    
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
            } else if model.isBatchComplete {
                batchCompleteView(geometry: geometry)
            } else if let error = model.error {
                errorView(geometry: geometry, errorMessage: error)
            } else {
                noPhotosView(geometry: geometry)
            }
        }
        // Only animate these state changes
        .animation(isAnimating ? .easeInOut(duration: swipeAnimationDuration) : nil, value: model.currentPhoto?.id)
        .animation(.easeInOut(duration: 0.3), value: model.isLoading)
        .animation(.easeInOut(duration: 0.3), value: model.isBatchComplete)
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
            // Add a placeholder for the next card if available
            if model.hasMorePhotos, model.currentIndex + 1 < model.photoAssets.count {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * 0.85, height: geometry.size.height * 0.8)
                    .cornerRadius(15)
                    .shadow(color: Color.gray.opacity(0.2), radius: 5, x: 0, y: 2)
                    .offset(y: 5)
                    .zIndex(0)
            }
            
            // Show current photo
            PhotoCardView(
                photo: currentPhoto,
                size: geometry.size,
                dragOffset: dragState,
                onSwiped: { _ in }, // This is handled by the gesture below
                isTopCard: true
            )
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
                            
                            withAnimation(.easeOut(duration: swipeAnimationDuration)) {
                                self.dragState.width = self.dragState.width > 0 ? 1000 : -1000
                                self.dragState.height = 100
                            }
                            
                            // Process the swipe after animation
                            Task {
                                try? await Task.sleep(for: .milliseconds(300))
                                await model.processSwipe(swipeDirection)
                                
                                // Reset animation state
                                self.dragState = .zero
                                self.isAnimating = false
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
}

// Preview provider
#Preview {
    SwipeablePhotoStack(model: PhotoViewModel())
} 