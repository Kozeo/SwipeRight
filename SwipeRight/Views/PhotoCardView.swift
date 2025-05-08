import SwiftUI
import Photos

struct PhotoCardView: View {
    let photo: PhotoModel
    let size: CGSize
    let dragOffset: CGSize
    let onSwiped: (SwipeDirection) async -> Void
    let isTopCard: Bool
    
    // Constants for the animation
    private let swipeThreshold: CGFloat = 120
    private let rotationFactor: Double = 12
    private let cornerRadius: CGFloat = 15
    
    // Computed properties for shadow color
    private var shadowColor: Color {
        if dragOffset.width > 30 {
            return Color.green.opacity(0.7)
        } else if dragOffset.width < -30 {
            return Color.red.opacity(0.7)
        } else {
            // Cyberpunk purple glow when card is not being swiped
            return Color(red: 0.5, green: 0.0, blue: 1.0).opacity(0.7)
        }
    }
    
    // Computed property for overlay opacity
    private var overlayOpacity: Double {
        return min(abs(Double(dragOffset.width) / 100), 1.0)
    }
    
    // Shadow optimization - use more dramatic shadow when not animating
    private var shadowRadius: CGFloat {
        return abs(dragOffset.width) > 5 ? 8 : 15
    }
    
    // Second shadow for cyberpunk effect
    private var outerGlowRadius: CGFloat {
        return abs(dragOffset.width) > 5 ? 4 : 10
    }
    
    // Use thumbnail during animations to improve performance
    private var displayImage: UIImage? {
        // Always use thumbnails during rapid animation or dragging
        if abs(dragOffset.width) > 50 {
            return photo.thumbnailImage ?? photo.image
        } else if isTopCard {
            // When it's the top card and not in rapid animation, use full image
            return photo.image
        } else {
            // For background cards, use the photo's position-based image selection
            return photo.imageForPosition(isTopCard: isTopCard)
        }
    }
    
    var body: some View {
        ZStack {
            // Outer glow effect - larger, more diffuse purple
            RoundedRectangle(cornerRadius: cornerRadius + 2)
                .fill(Color.clear)
                .shadow(color: Color(red: 0.6, green: 0.2, blue: 1.0).opacity(0.4), 
                        radius: outerGlowRadius + 5, x: 0, y: 0)
                .frame(width: size.width * 0.9 + 4, height: size.height * 0.85 + 4)
            
            // Base white background with shadow
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white)
                .shadow(color: shadowColor,
                        radius: shadowRadius, x: 0, y: 2)
                .frame(width: size.width * 0.9, height: size.height * 0.85)
            
            // Content container
            VStack(spacing: 0) {
                if let creationDate = photo.creationDate {
                    Text(dateFormatter.string(from: creationDate))
                        .font(.headline)
                        .padding(.top, 15)
                        .padding(.bottom, 5)
                }
                
                // Image container with proper clipping
                if let image = displayImage {
                    ZStack {
                        // Image with proper scaling
                        Image(uiImage: image)
                            .interpolation(.high) // Use high interpolation quality
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: size.width * 0.85, maxHeight: size.height * 0.65)
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
                    .padding(.top, 5)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(3/4, contentMode: .fit)
                            .frame(maxWidth: size.width * 0.85, maxHeight: size.height * 0.65)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            )
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 15)
                    .padding(.top, 5)
                }
            }
            .frame(width: size.width * 0.9, height: size.height * 0.85)
            
            // Colored border overlay - properly aligned with card bounds
            if isTopCard {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        dragOffset.width > 30 ? Color.green : 
                        dragOffset.width < -30 ? Color.red : 
                        Color.clear,
                        lineWidth: 4
                    )
                    .frame(width: size.width * 0.9, height: size.height * 0.85)
                    .opacity(overlayOpacity)
            }
            
            // Text indicator overlays
            if isTopCard {
                // Keep overlay (green)
                if dragOffset.width > 30 {
                    VStack {
                        Text("KEEP")
                            .font(.headline)
                            .padding(8)
                            .background(Color.green.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)
                    .frame(width: size.width * 0.9, height: size.height * 0.85, alignment: .top)
                    .opacity(overlayOpacity)
                }
                
                // Archive overlay (red)
                if dragOffset.width < -30 {
                    VStack {
                        Text("ARCHIVE")
                            .font(.headline)
                            .padding(8)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)
                    .frame(width: size.width * 0.9, height: size.height * 0.85, alignment: .top)
                    .opacity(overlayOpacity)
                }
            }
            
            // Subtle inner border to enhance the cyberpunk effect - correctly aligned
            RoundedRectangle(cornerRadius: cornerRadius - 1)
                .stroke(Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.3), lineWidth: 1)
                .frame(width: size.width * 0.9 - 2, height: size.height * 0.85 - 2)
        }
        .frame(width: size.width * 0.9, height: size.height * 0.85)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .id(photo.id) // Ensure view is refreshed when photo changes
        // Apply .drawingGroup() for better rendering performance
        .drawingGroup()
        // Disable animation for transitions to prevent flicker
        .animation(nil, value: photo.id)
    }
    
    // Date formatter for displaying the photo date
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

// Preview provider
#Preview {
    let placeholderAsset = PHAsset()
    let placeholderImage = UIImage(systemName: "photo")
    let photo = PhotoModel(asset: placeholderAsset, image: placeholderImage)
    
    return PhotoCardView(
        photo: photo,
        size: CGSize(width: 350, height: 500),
        dragOffset: CGSize.zero,
        onSwiped: { _ in },
        isTopCard: true
    )
} 
