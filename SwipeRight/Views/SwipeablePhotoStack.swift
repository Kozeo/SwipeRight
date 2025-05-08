import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    let model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var isAnimating: Bool = false
    @State private var isTransitioning: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Constants
    private enum Constants {
        static let swipeThreshold: CGFloat = 100.0
        static let rotationFactor: Double = 35.0
        static let swipeAnimationDuration: Double = 0.3
        static let cardCornerRadius: CGFloat = 15.0
        static let animationDuration: Double = 0.3
    }
    
    // Computed color properties for dynamic styling
    private var primaryGlowColor: Color {
        colorScheme == .dark ? 
            Color(red: 0.6, green: 0.3, blue: 1.0) : 
            Color(red: 0.5, green: 0.0, blue: 1.0)
    }
    
    // Computed property to determine if we're on a high-performance device
    private var isHighPerformanceDevice: Bool {
        ProcessInfo.processInfo.physicalMemory >= 4_000_000_000
    }
    
    var body: some View {
        GeometryReader { geometry in
            contentView(geometry: geometry)
                .transition(.opacity)
                // Only animate specific state changes, not stack positions
                .animation(.easeInOut(duration: Constants.animationDuration), value: model.isLoading)
                .animation(.easeInOut(duration: Constants.animationDuration), value: model.isBatchComplete)
                .animation(.easeInOut(duration: Constants.animationDuration), value: model.error)
                // Explicitly disable animations for stack changes
                .animation(nil, value: model.visiblePhotoStack)
                .environment(\.isEnabled, !isAnimating)
        }
    }
    
    // MARK: - Content Views
    
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
    
    // MARK: - Card Stack
    
    private func cardStackView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background container with extra space to prevent clipping
            Color.clear
                .frame(
                    width: geometry.size.width * 1.5,
                    height: geometry.size.height * 1.5
                )
            
            // Stack container
            ZStack {
                // Background glow for high-performance devices
                if isHighPerformanceDevice {
                    backgroundGlow(geometry: geometry)
                }
                
                // Background cards in reverse stack order
                renderBackgroundCards(geometry: geometry)
                
                // Top card
                if !model.visiblePhotoStack.isEmpty {
                    topCardView(for: model.visiblePhotoStack[0], geometry: geometry)
                }
            }
            .allowsHitTesting(!isAnimating)
        }
        .padding()
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isAnimating {
                        handleDragChange(gesture)
                    }
                }
                .onEnded { gesture in
                    if !isAnimating {
                        handleDragEnd(gesture)
                    }
                }
        )
    }
    
    // Function to render background cards in reverse stack order
    private func renderBackgroundCards(geometry: GeometryProxy) -> some View {
        Group {
            // Card 3 (if available)
            if model.visiblePhotoStack.count >= 3 {
                cardView(for: model.visiblePhotoStack[2], at: 2, geometry: geometry)
                    .animation(nil, value: model.visiblePhotoStack)
            }
            
            // Card 2 (if available)
            if model.visiblePhotoStack.count >= 2 {
                cardView(for: model.visiblePhotoStack[1], at: 1, geometry: geometry)
                    .animation(nil, value: model.visiblePhotoStack)
            }
        }
    }
    
    // MARK: - Card Components
    
    private func backgroundGlow(geometry: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: Constants.cardCornerRadius + 5)
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
            .zIndex(-999)
    }
    
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
            .rotationEffect(.degrees(Double(dragState.width) / Constants.rotationFactor))
            .zIndex(100)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 5)
            .animation(isAnimating ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: dragState)
        }
        .frame(
            width: geometry.size.width * 1.2,
            height: geometry.size.height * 1.1
        )
    }
    
    private func topCardGlow(geometry: GeometryProxy) -> some View {
        let glowColor = dragState.width > 30 ? .green.opacity(0.6) :
                       dragState.width < -30 ? .red.opacity(0.6) :
                       primaryGlowColor.opacity(0.6)
        
        return RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
            .fill(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                    .stroke(glowColor, lineWidth: 2)
            )
            .blur(radius: 3)
            .opacity(0.7)
            .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.85)
            .offset(x: dragState.width, y: dragState.height)
            .rotationEffect(.degrees(Double(dragState.width) / Constants.rotationFactor))
            .zIndex(99)
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
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
        
        if abs(self.dragState.width) > Constants.swipeThreshold {
            processSwipe(gesture)
        } else {
            resetDragState()
        }
    }
    
    private func processSwipe(_ gesture: DragGesture.Value) {
        let swipeDirection: SwipeDirection = self.dragState.width > 0 ? .right : .left
        
        // Set animating flags
        isAnimating = true
        isTransitioning = true
        
        // Calculate screen width
        let screenWidth = UIScreen.main.bounds.width
        
        // Animate card off screen
        withAnimation(.easeOut(duration: Constants.swipeAnimationDuration)) {
            self.dragState.width = gesture.translation.width > 0 
                ? screenWidth * 1.5
                : -screenWidth * 1.5
            
            // Add slight vertical movement based on gesture
            let verticalRatio = gesture.translation.height / max(abs(gesture.translation.width), 1)
            self.dragState.height = verticalRatio * 150
        }
        
        // Process swipe after animation
        Task {
            // Wait for exit animation to complete
            try? await Task.sleep(for: .milliseconds(Int(Constants.swipeAnimationDuration * 1000)))
            
            // Reset drag state BEFORE updating the model
            await MainActor.run {
                withAnimation(nil) {
                    self.dragState = .zero
                }
            }
            
            // Process the swipe in the model
            await model.processSwipe(swipeDirection)
            
            // Add a slight delay before re-enabling animations
            try? await Task.sleep(for: .milliseconds(150))
            
            // Re-enable animations
            await MainActor.run {
                self.isAnimating = false
                
                // Small delay before resetting transition state
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    self.isTransitioning = false
                }
            }
        }
    }
    
    private func resetDragState() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            self.dragState = .zero
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
                    await startNewBatch()
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
    
    private func startNewBatch() async {
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
                openSettings()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding()
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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

