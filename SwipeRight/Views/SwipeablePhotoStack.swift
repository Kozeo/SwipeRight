import SwiftUI
import Photos

struct SwipeablePhotoStack: View {
    let model: PhotoViewModel
    @State private var dragState = CGSize.zero
    @State private var cardRotation: Double = 0
    @State private var isAnimating: Bool = false
    @State private var isTransitioning: Bool = false
    @State private var draggedCardScale: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    // Constants
    private let swipeThreshold: CGFloat = 100.0
    private let rotationFactor: Double = 35.0
    private let swipeAnimationDuration: Double = 0.3
    private let maxCardLift: CGFloat = 10.0
    
    // Stack visual constants
    private let stackSpacing: CGFloat = 10.0
    private let stackScaleDecrement: CGFloat = 0.06
    private let cardCornerRadius: CGFloat = 15.0
    
    // EquatableKey for optimizing list rendering performance 
    private struct CardIdentifier: Equatable, Hashable {
        let id: String
        let zIndex: Double
        let isTopCard: Bool
    }
    
    // Computed color properties for dynamic styling
    private var primaryGlowColor: Color {
        colorScheme == .dark ? 
            Color(red: 0.6, green: 0.3, blue: 1.0) : 
            Color(red: 0.5, green: 0.0, blue: 1.0)
    }
    
    private var secondaryGlowColor: Color {
        colorScheme == .dark ? 
            Color(red: 0.2, green: 0.7, blue: 0.9) : 
            Color(red: 0.0, green: 0.6, blue: 1.0)
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
            ZStack {
                // Always show the photo stack if it's not empty, even during transitions
                if !model.visiblePhotoStack.isEmpty {
                    photoStackView(geometry: geometry)
                        // Turn off animations completely when updating stack positions
                        // This eliminates flickering between cards 
                        .animation(nil, value: model.visiblePhotoStack.count)
                } else if model.isLoading && !isTransitioning {
                    // Show loading only for initial loading, not transitions
                    loadingView
                } else if model.isBatchComplete {
                    batchCompleteView(geometry: geometry)
                } else if let error = model.error {
                    errorView(geometry: geometry, errorMessage: error)
                } else {
                    // Only show no photos if we're not in a transition
                    noPhotosView(geometry: geometry)
                }
            }
        }
        // Use explicit animations only for state changes
        .animation(.easeInOut(duration: 0.3), value: model.isLoading)
        .animation(.easeInOut(duration: 0.3), value: model.isBatchComplete)
        // Disable animations for stack preparation to avoid flickering
        .animation(nil, value: model.isPreparingStack)
    }
    
    // MARK: - Component Views
    
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
    
    private func photoStackView(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background gradient for enhanced depth - only render on high performance devices
            if isHighPerformanceDevice {
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
            }
            
            // Safe copy of the current stack to prevent changes during iteration
            let visibleStack = model.visiblePhotoStack
                
            // Create array of card identifiers for equatable rendering
            let cardIdentifiers = visibleStack.enumerated().map { index, photo in
                CardIdentifier(id: photo.id, zIndex: photo.zIndex, isTopCard: index == 0)
            }
            
            // Use ForEach with identifiable, equatable elements for better diffing
            // Disable automatic animations for ForEach to prevent unwanted transitions
            ForEach(visibleStack.indices.reversed(), id: \.self) { index in
                let photo = visibleStack[index]
                let isTopCard = index == 0
                
                // Only render visible cards (performance optimization)
                if index < 3 || isHighPerformanceDevice {
                    cardView(for: photo, at: index, in: geometry)
                        // Use key to prevent unnecessary re-renders when only dragState changes
                        .id(cardIdentifiers[index])
                }
            }
            // Apply animation modifier only to explicit state changes
            // This prevents implicit animations during ForEach updates
            .animation(nil, value: UUID())
        }
        .padding()
        .frame(width: geometry.size.width, height: geometry.size.height)
        // Add a gesture to the entire stack container for better performance
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
    
    private func cardView(for photo: PhotoModel, at index: Int, in geometry: GeometryProxy) -> some View {
        let isTopCard = index == 0
        let cardView = PhotoCardView(
            photo: photo,
            size: geometry.size,
            dragOffset: isTopCard ? dragState : .zero,
            onSwiped: { _ in },
            isTopCard: isTopCard
        )
        
        // Enhanced card styling based on position in stack
        let stackDepth = CGFloat(index)
        
        if isTopCard {
            // Top card with enhanced dynamic styling
            // Dynamic glow effect variables that change based on drag direction
            let dragRatio = min(abs(dragState.width) / 200, 1.0)
            let dragDirection = dragState.width > 0 ? 1.0 : -1.0
            let glowColor = dragState.width > 30 ? Color.green.opacity(0.6) :
                            dragState.width < -30 ? Color.red.opacity(0.6) :
                            primaryGlowColor.opacity(0.6)
            
            return AnyView(
                ZStack {
                    // Only render enhanced effects on high performance devices
                    if isHighPerformanceDevice {
                        // Enhanced glow effect
                        RoundedRectangle(cornerRadius: cardCornerRadius)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: cardCornerRadius)
                                    .stroke(glowColor, lineWidth: 2)
                            )
                            .blur(radius: 3)
                            .offset(x: dragDirection * dragRatio * 2)
                            .scaleEffect(draggedCardScale + 0.01)
                            .opacity(0.7)
                    }
                    
                    // Actual card
                    cardView
                        .overlay(
                            RoundedRectangle(cornerRadius: cardCornerRadius)
                                .stroke(
                                    dragState.width > 30 ? Color.green.opacity(dragRatio * 0.8) :
                                    dragState.width < -30 ? Color.red.opacity(dragRatio * 0.8) :
                                    Color.clear,
                                    lineWidth: 3
                                )
                        )
                }
                .scaleEffect(draggedCardScale)
                .offset(x: dragState.width, y: dragState.height + photo.offset.height)
                .rotationEffect(.degrees(Double(dragState.width) / rotationFactor))
                .zIndex(photo.zIndex)
                // Create more dramatic shadow for top card
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 5)
                .shadow(color: isHighPerformanceDevice ? glowColor.opacity(0.3) : .clear, radius: 12, x: 0, y: 0)
                // Remove transition effects for smooth forward movement
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: dragState)
            )
        } else {
            // Enhanced background card styling
            let dragInfluence = min(abs(dragState.width) / 500, 1.0) // Normalize influence
            let dragDirection = dragState.width > 0 ? 1.0 : -1.0
            
            // Enhanced background movement - more dynamic response
            let horizontalShift = isAnimating ? 0 : dragDirection * dragInfluence * 8.0 * (1.0 / CGFloat(index + 1))
            let verticalShift = isAnimating ? 0 : min(abs(dragState.height), 30) * 0.4 * (1.0 / CGFloat(index + 1))
            let baseScale = photo.scale + (dragInfluence * 0.03 * (1.0 / CGFloat(index + 1)))
            
            // Invert direction slightly for cards deep in the stack for parallax effect
            let parallaxFactor = index >= 2 ? -0.3 : 1.0
            
            // Enhanced dynamic offset with parallax effect
            let dynamicOffset = CGSize(
                width: photo.offset.width + (horizontalShift * parallaxFactor),
                height: photo.offset.height - verticalShift
            )
            
            // Enhanced shadow and lighting properties based on stack depth
            let shadowOpacity = max(0.1, 0.25 - (stackDepth * 0.05))
            let shadowRadius = max(2, 6 - (stackDepth * 1.5))
            let shadowOffsetY = max(1, 4 - stackDepth)
            
            return AnyView(
                ZStack {
                    // Only render ambient glow on high performance devices
                    if isHighPerformanceDevice {
                        // Slight ambient glow for background cards
                        RoundedRectangle(cornerRadius: cardCornerRadius)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: cardCornerRadius)
                                    .stroke(secondaryGlowColor.opacity(0.2 - (stackDepth * 0.05)), lineWidth: 1)
                            )
                            .blur(radius: 2)
                            .scaleEffect(baseScale + 0.01)
                            .offset(dynamicOffset)
                    }
                    
                    // Card with depth-based styling
                    cardView
                }
                .scaleEffect(baseScale)
                .offset(dynamicOffset)
                .zIndex(photo.zIndex)
                // Graduated shadows based on stack depth
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: shadowRadius,
                    x: 0,
                    y: shadowOffsetY
                )
                // Additional subtle colored shadow only on high performance devices
                .shadow(
                    color: isHighPerformanceDevice ? secondaryGlowColor.opacity(0.1 - (stackDepth * 0.03)) : .clear,
                    radius: isHighPerformanceDevice ? 15 : 0,
                    x: 0,
                    y: 0
                )
                // Remove transition effects for smooth forward movement
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dragState)
            )
        }
    }
    
    // MARK: - Gesture Handlers
    
    private func handleDragChange(_ gesture: DragGesture.Value) {
        guard !isAnimating, !model.visiblePhotoStack.isEmpty else { return }
        
        self.dragState = gesture.translation
        self.cardRotation = Double(gesture.translation.width) / rotationFactor
        
        // Calculate a slight scale increase when dragging to provide tactile feedback
        let dragDistance = sqrt(pow(gesture.translation.width, 2) + pow(gesture.translation.height, 2))
        let scaleFactor = min(dragDistance / 500, 0.05)
        self.draggedCardScale = 1.0 + scaleFactor
    }
    
    private func handleDragEnd(_ gesture: DragGesture.Value) {
        guard !isAnimating, !model.visiblePhotoStack.isEmpty else { return }
        
        if abs(self.dragState.width) > swipeThreshold {
            // Determine swipe direction
            let swipeDirection: SwipeDirection = self.dragState.width > 0 ? .right : .left
            
            // Set animating flag
            isAnimating = true
            
            // Calculate screen dimensions to ensure card moves fully off screen
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            
            // Calculate exit target angle for more natural movement
            let exitAngle = Double(gesture.translation.width > 0 ? 15 : -15)
            
            // Animate the card off screen with enhanced effects
            withAnimation(.easeOut(duration: swipeAnimationDuration)) {
                // Ensure card moves completely off screen in the swipe direction
                self.dragState.width = gesture.translation.width > 0 
                    ? screenWidth * 1.5 // Move further to ensure it's offscreen
                    : -screenWidth * 1.5
                
                // Apply vertical movement for more natural effect based on gesture
                let verticalRatio = gesture.translation.height / max(abs(gesture.translation.width), 1)
                self.dragState.height = verticalRatio * screenHeight * 0.5
                
                // Set rotation for natural feel
                self.cardRotation = exitAngle
                
                // Slightly scale down as card exits
                self.draggedCardScale = 0.95
            }
            
            // Process the swipe after animation
            Task {
                // Wait for the animation to complete
                try? await Task.sleep(for: .milliseconds(Int(swipeAnimationDuration * 1000)))
                
                // Set transitioning state to true before clearing the current photo
                await MainActor.run {
                    isTransitioning = true
                }
                
                // Process the swipe which will update the stack
                await model.processSwipe(swipeDirection)
                
                // Reset animation flags after processing
                await MainActor.run {
                    // Reset drag state AFTER the card is removed from the stack
                    self.dragState = .zero
                    self.cardRotation = 0
                    self.draggedCardScale = 1.0
                    self.isAnimating = false
                    self.isTransitioning = false
                }
            }
        } else {
            // Reset if not swiped enough with enhanced spring animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.2)) {
                self.dragState = .zero
                self.cardRotation = 0
                self.draggedCardScale = 1.0
            }
        }
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
                        draggedCardScale = 1.0
                        cardRotation = 0
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