import SwiftUI
import Photos

struct PhotoCardView: View {
    let photo: PhotoModel
    let onSwiped: (SwipeDirection) async -> Void
    
    // State for the swipe animation
    @State private var offset: CGSize = .zero
    @State private var swipeDirection: SwipeDirection = .none
    @State private var isAnimatingOut = false
    
    // Constants for the animation
    private let swipeThreshold: CGFloat = 120
    private let rotationAngle: Double = 12
    
    var body: some View {
        ZStack {
            // Background for when the card is swiped away
            Color.clear
            
            // Card content
            VStack {
                if let creationDate = photo.creationDate {
                    Text(dateFormatter.string(from: creationDate))
                        .font(.headline)
                        .padding(.top)
                }
                
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(10)
                        .padding()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(3/4, contentMode: .fit)
                        .cornerRadius(10)
                        .padding()
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(15)
            .shadow(radius: 5)
            .overlay(
                ZStack {
                    // Keep overlay (green halo)
                    if swipeDirection == .right {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.green, lineWidth: 4)
                            .overlay(
                                VStack {
                                    Text("KEEP")
                                        .font(.headline)
                                        .padding(8)
                                        .background(Color.green.opacity(0.8))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 20), 
                                alignment: .top
                            )
                            .opacity(min(abs(offset.width) / 100, 1.0))
                    }
                    
                    // Archive overlay (red text)
                    if swipeDirection == .left {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.red, lineWidth: 4)
                            .overlay(
                                VStack {
                                    Text("ARCHIVE")
                                        .font(.headline)
                                        .padding(8)
                                        .background(Color.red.opacity(0.8))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 20),
                                alignment: .top
                            )
                            .opacity(min(abs(offset.width) / 100, 1.0))
                    }
                }
            )
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 20) * rotationAngle / 15))
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        guard !isAnimatingOut else { return }
                        offset = gesture.translation
                        
                        // Determine swipe direction
                        if offset.width > 20 {
                            swipeDirection = .right
                        } else if offset.width < -20 {
                            swipeDirection = .left
                        } else {
                            swipeDirection = .none
                        }
                    }
                    .onEnded { gesture in
                        guard !isAnimatingOut else { return }
                        
                        // Handle swipe based on threshold
                        if abs(offset.width) > swipeThreshold {
                            // Swipe completed, move the card away
                            let direction: SwipeDirection = offset.width > 0 ? .right : .left
                            
                            // Animate the card off-screen with easing
                            isAnimatingOut = true
                            let screenWidth = UIScreen.main.bounds.width
                            withAnimation(.easeOut(duration: 0.3)) {
                                offset.width = direction == .right ? screenWidth * 1.5 : -screenWidth * 1.5
                                offset.height = 100 // Add a little vertical movement for a more natural feel
                            }
                            
                            // Notify about swipe action after animation completes
                            Task {
                                try? await Task.sleep(for: .milliseconds(300))
                                await onSwiped(direction)
                            }
                        } else {
                            // Reset if not swiped enough
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                offset = .zero
                                swipeDirection = .none
                            }
                        }
                    }
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: swipeDirection)
        }
    }
    
    // Date formatter for displaying the photo date
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

// Preview provider for PhotoCardView
#Preview {
    let placeholderAsset = PHAsset()
    let placeholderImage = UIImage(systemName: "photo")
    let photo = PhotoModel(asset: placeholderAsset, image: placeholderImage)
    
    return PhotoCardView(photo: photo) { _ in
        // Preview doesn't need to do anything with the swipe
    }
} 