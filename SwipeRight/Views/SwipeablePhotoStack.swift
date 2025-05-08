import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    let model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var isAnimating: Bool = false
    @State private var isTransitioning: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Constants
    private let swipeThreshold: CGFloat = 100.0
    private let rotationFactor: Double = 35.0
    private let swipeAnimationDuration: Double = 0.3
    private let cardCornerRadius: CGFloat = 15.0
    
    // Computed color properties for dynamic styling
    private var primaryGlowColor: Color {
        colorScheme == .dark ? 
            Color(red: 0.6, green: 0.3, blue: 1.0) : 
            Color(red: 0.5, green: 0.0, blue: 1.0)
    }
    
    // Computed property to determine if we're on a high-performance device
    private var isHighPerformanceDevice: Bool {
        // Use device RAM as a proxy for performance capabilities
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        // 4GB or more is considered high performance
        return physicalMemory >= 4_000_000_000
    }
    
    var body: some View {
        GeometryReader { geometry in
            contentView(geometry: geometry)
                // Only animate state changes, not stack positions
                .animation(.easeInOut(duration: 0.3), value: model.isLoading)
                .animation(.easeInOut(duration: 0.3), value: model.isBatchComplete)
                .animation(nil, value: model.visiblePhotoStack)
        }
    }
    
    // Main content view based on state
    private func contentView(geometry: GeometryProxy) -> some View {
        Group {
            if !model.visiblePhotoStack.isEmpty {
                cardStackView(geometry: geometry)
            } else if model.isLoading {
                loadingView
            } else if model.isBatchComplete {
                batchCompleteView(geometry: geometry)
            } else if let error = model.error {
                errorView(geometry: geometry, errorMessage: error)
            } else {
                noPhotosView(geometry: geometry)
            }
        }
    }
    
    // Card stack view with all cards
    private func cardStackView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background
            if isHighPerformanceDevice {
                backgroundGlow(geometry: geometry)
            }
            
            // Card 3 (if available)
            if model.visiblePhotoStack.count >= 3 {
                cardView(for: model.visiblePhotoStack[2], at: 2, geometry: geometry)
            }
            
            // Card 2 (if available)
            if model.visiblePhotoStack.count >= 2 {
                cardView(for: model.visiblePhotoStack[1], at: 1, geometry: geometry)
            }
            
            // Top card
            if !model.visiblePhotoStack.isEmpty {
                topCardView(for: model.visiblePhotoStack[0], geometry: geometry)
            }
        }
        .padding()
        .frame(width: geometry.size.width, height: geometry.size.height)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    handleDragChange(gesture)
                }
                .onEnded { gesture in
                    handleDragEnd(gesture)
                }
        )
    }
    
    // Background gradient glow
    private func backgroundGlow(geometry: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: cardCornerRadius + 5)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.6),
                        Color.black.opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 20)
            .opacity(0.3)
            .frame(
                width: geometry.size.width * 0.9 + 20,
                height: geometry.size.height * 0.85 + 20
            )
            .offset(y: 10)
            // Ensure background glow has the lowest z-index
            .zIndex(-999)
    }
    
    // Background card at a specific position
    private func cardView(for photo: PhotoModel, at position: Int, geometry: GeometryProxy) -> some View {
        let scaleValue = 1.0 - (0.05 * CGFloat(position))
        let offsetValue = -8.0 * CGFloat(position)
        
        return PhotoCardView(
            photo: photo,
            size: geometry.size,
            dragOffset: .zero,
            onSwiped: { _ in },
            isTopCard: false
        )
        .scaleEffect(scaleValue)
        .offset(y: offsetValue)
        .zIndex(-Double(position))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
    
    // Top card that can be dragged
    private func topCardView(for photo: PhotoModel, geometry: GeometryProxy) -> some View {
        ZStack {
            // Glow effect when dragging (only on high performance devices)
            if isHighPerformanceDevice && abs(dragState.width) > 30 {
                topCardGlow(geometry: geometry)
            }
            
            // Main card
            PhotoCardView(
                photo: photo,
                size: geometry.size,
                dragOffset: dragState,
                onSwiped: { _ in },
                isTopCard: true
            )
            .overlay(cardBorder)
            .offset(x: dragState.width, y: dragState.height)
            .rotationEffect(.degrees(Double(dragState.width) / rotationFactor))
            .zIndex(100)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 5)
            .animation(isAnimating ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: dragState)
        }
    }
    
    // Top card glow effect
    private func topCardGlow(geometry: GeometryProxy) -> some View {
        let glowColor: Color = dragState.width > 30 ? .green.opacity(0.6) :
                              dragState.width < -30 ? .red.opacity(0.6) :
                              Color(red: 0.5, green: 0.0, blue: 1.0).opacity(0.6)
        
        return RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(glowColor, lineWidth: 2)
            )
            .blur(radius: 3)
            .opacity(0.7)
            .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.85)
            .offset(x: dragState.width, y: dragState.height)
            .rotationEffect(.degrees(Double(dragState.width) / rotationFactor))
            .zIndex(99)
    }
    
    // Card border that changes color based on drag direction
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .stroke(
                dragState.width > 30 ? Color.green.opacity(0.8) :
                dragState.width < -30 ? Color.red.opacity(0.8) :
                Color.clear,
                lineWidth: 3
            )
    }
    
    // MARK: - Gesture Handlers
    
    private func handleDragChange(_ gesture: DragGesture.Value) {
        guard !isAnimating, !model.visiblePhotoStack.isEmpty else { return }
        self.dragState = gesture.translation
    }
    
    private func handleDragEnd(_ gesture: DragGesture.Value) {
        guard !isAnimating, !model.visiblePhotoStack.isEmpty else { return }
        
        if abs(self.dragState.width) > swipeThreshold {
            let swipeDirection: SwipeDirection = self.dragState.width > 0 ? .right : .left
            
            // Set animating flag
            isAnimating = true
            isTransitioning = true
            
            // Calculate screen width
            let screenWidth = UIScreen.main.bounds.width
            
            // Animate card off screen
            withAnimation(.easeOut(duration: swipeAnimationDuration)) {
                self.dragState.width = gesture.translation.width > 0 
                    ? screenWidth * 1.5
                    : -screenWidth * 1.5
                
                // Add slight vertical movement based on gesture
                let verticalRatio = gesture.translation.height / max(abs(gesture.translation.width), 1)
                self.dragState.height = verticalRatio * 150
            }
            
            // Process swipe after animation
            Task {
                // Wait for animation to complete
                try? await Task.sleep(for: .milliseconds(Int(swipeAnimationDuration * 1000)))
                
                // Reset drag state BEFORE updating the model
                await MainActor.run {
                    withAnimation(nil) {
                        self.dragState = .zero
                    }
                }
                
                // Process the swipe in the model
                await model.processSwipe(swipeDirection)
                
                // Allow time for model updates to complete
                try? await Task.sleep(for: .milliseconds(100))
                
                // Re-enable animations
                await MainActor.run {
                    self.isAnimating = false
                    
                    // Small delay before resetting transition state
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        self.isTransitioning = false
                    }
                }
            }
        } else {
            // Reset if not swiped enough
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                self.dragState = .zero
            }
        }
    }
    
    // MARK: - UI States
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding()
            
            Text(isTransitioning ? "Loading next photo..." : "Loading photos...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
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
                    // Reset all flags first to avoid UI state issues
                    await MainActor.run {
                        isTransitioning = true
                        isAnimating = false
                        dragState = .zero
                    }
                    
                    // Load a new batch
                    await model.startNewBatch()
                    
                    // Reset transition state
                    await MainActor.run {
                        isTransitioning = false
                    }
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
                    // Set transitioning to true during refresh
                    isTransitioning = true
                    await model.startNewBatch()
                    isTransitioning = false
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

// Safe array indexing extension - using fileprivate to avoid conflicts with global extensions
fileprivate extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 

