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
                        // CRITICAL FIX: Explicitly disable animations for stack updates
                        .animation(nil, value: model.visiblePhotoStack)
                        .animation(nil, value: isTransitioning)
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
        // CRITICAL FIX: Additional animation control at the container level
        .animation(nil, value: model.visiblePhotoStack)
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
            
            // CRITICAL FIX: Wrap the entire stack in a ZStack with animation control
            ZStack {
                // Fixed, static stack instead of ForEach to avoid animation issues
                // Get the current stack
                let stack = model.visiblePhotoStack
                
                // IMPORTANT: Disable ALL animations for stack updates
                // by wrapping the entire stack in an animation modifier
                ZStack {
                    // Display up to 3 static card views based on what's available in the stack
                    // IMPORTANT: This completely avoids the ForEach animation issues
                    
                    // Card 3 (furthest back)
                    if stack.count >= 3, let photo = stack[safe: 2] {
                        staticCardView(photo: photo, index: 2, geometry: geometry)
                    }
                    
                    // Card 2 (middle)
                    if stack.count >= 2, let photo = stack[safe: 1] {
                        staticCardView(photo: photo, index: 1, geometry: geometry)
                    }
                    
                    // Card 1 (top card)
                    if !stack.isEmpty, let photo = stack[safe: 0] {
                        staticCardView(photo: photo, index: 0, geometry: geometry)
                    }
                }
                // CRITICAL: Use explicit animation control for stack updates
                .animation(nil, value: stack.count)
                .animation(nil, value: model.isPreparingStack)
                .animation(nil, value: isTransitioning)
            }
            .animation(nil, value: model.visiblePhotoStack) // CRITICAL FIX: Additional animation control
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
    
    private func staticCardView(photo: PhotoModel, index: Int, geometry: GeometryProxy) -> some View {
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
                .zIndex(3) // Explicitly use 3 for top card
                // Create more dramatic shadow for top card
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 5)
                .shadow(color: isHighPerformanceDevice ? glowColor.opacity(0.3) : .clear, radius: 12, x: 0, y: 0)
                // Only animate drag changes
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: dragState)
                .animation(nil, value: UUID()) // Prevent animations for view updates
            )
        } else {
            // Enhanced background card styling with STATIC positioning
            // Use fixed zIndex values rather than photo.zIndex
            let zIndexValue = index == 1 ? 2.0 : 1.0
            
            // Use static scale values instead of photo.scale
            let scaleValue = index == 1 ? 0.95 : 0.9
            
            // Use static offset values instead of photo.offset
            let offsetValue = CGSize(width: 0, height: -8.0 * CGFloat(index))
            
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
                            .scaleEffect(scaleValue + 0.01)
                            .offset(offsetValue)
                    }
                    
                    // Card with depth-based styling
                    cardView
                }
                .scaleEffect(scaleValue)
                .offset(offsetValue)
                .zIndex(zIndexValue)
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
                // Disable ALL animations for non-top cards
                .animation(nil, value: UUID())
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
            
            // Set animating flag immediately to prevent multiple swipes
            isAnimating = true
            isTransitioning = true  // Set flag to prevent stack animations
            
            // Calculate screen width for animation
            let screenWidth = UIScreen.main.bounds.width
            
            // PHASE 1: Animate the card flying off screen
            withAnimation(.easeOut(duration: swipeAnimationDuration)) {
                // Animate swiped card off screen
                self.dragState.width = gesture.translation.width > 0 
                    ? screenWidth * 1.5
                    : -screenWidth * 1.5
                
                // Natural vertical movement based on gesture
                let verticalRatio = gesture.translation.height / max(abs(gesture.translation.width), 1)
                self.dragState.height = verticalRatio * 200  // Limit vertical movement
                
                // Natural rotation
                self.cardRotation = Double(gesture.translation.width > 0 ? 15 : -15)
                self.draggedCardScale = 0.95
            }
            
            // Process the swipe after animation in multiple phases
            Task {
                // Wait for "card leaving" animation to complete
                try? await Task.sleep(for: .milliseconds(Int(swipeAnimationDuration * 1000)))
                
                // PHASE 2: Reset UI state with NO animation
                await MainActor.run {
                    // Important: Use withAnimation(nil) to explicitly disable animations
                    withAnimation(nil) {
                        self.dragState = .zero
                        self.cardRotation = 0
                        self.draggedCardScale = 1.0
                    }
                }
                
                // Small pause to ensure UI updates are complete
                try? await Task.sleep(for: .milliseconds(50))
                
                // PHASE 3: Update model state (this triggers the stack update)
                await model.processSwipe(swipeDirection)
                
                // Wait for the model to finish processing
                try? await Task.sleep(for: .milliseconds(200))
                
                // PHASE 4: Restore normal UI behavior
                await MainActor.run {
                    // First allow animation but keep transition flag
                    isAnimating = false
                    
                    // Wait a bit longer before enabling transitions
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        // Finally, clear the transition flag when everything is stable
                        isTransitioning = false
                    }
                }
            }
        } else {
            // Not swiped enough - reset card position with spring animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
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

// Safe array indexing extension - using fileprivate to avoid conflicts with global extensions
fileprivate extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 