import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    @ObservedObject var model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var cardRotation: Double = 0
    
    // Constants
    private let swipeThreshold: CGFloat = 100.0
    private let rotationFactor: Double = 35.0
    
    var body: some View {
        GeometryReader { geometry in
            if model.isLoading {
                // Loading state
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Loading photos...")
                        .font(.headline)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .transition(.opacity)
            } else if let currentPhoto = model.currentPhoto {
                // Photo stack with current photo
                ZStack {
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
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                self.dragState = gesture.translation
                                self.cardRotation = Double(gesture.translation.width) / rotationFactor
                            }
                            .onEnded { _ in
                                if abs(self.dragState.width) > swipeThreshold {
                                    let swipeDirection: SwipeDirection = self.dragState.width > 0 ? .right : .left
                                    
                                    withAnimation(.easeOut(duration: 0.5)) {
                                        self.dragState.width = self.dragState.width > 0 ? 1000 : -1000
                                        self.dragState.height = 100
                                    }
                                    
                                    // Process the swipe after animation
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(300))
                                        await model.processSwipe(swipeDirection)
                                        self.dragState = .zero
                                    }
                                } else {
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
            } else if model.isBatchComplete {
                // Batch complete view
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
            } else if let error = model.error {
                // Error state
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .padding()
                    
                    Text(error)
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
            } else {
                // No photos available
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
        .animation(.easeInOut(duration: 0.3), value: model.currentPhoto?.id)
        .animation(.easeInOut(duration: 0.3), value: model.isLoading)
        .animation(.easeInOut(duration: 0.3), value: model.isBatchComplete)
    }
}

// Preview provider
#Preview {
    SwipeablePhotoStack(model: PhotoViewModel())
} 