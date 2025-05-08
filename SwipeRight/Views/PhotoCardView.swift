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
    
    // Computed properties for shadow color
    private var shadowColor: Color {
        if dragOffset.width > 30 {
            return Color.green.opacity(0.5)
        } else if dragOffset.width < -30 {
            return Color.red.opacity(0.5)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    // Computed property for overlay opacity
    private var overlayOpacity: Double {
        return min(abs(Double(dragOffset.width) / 100), 1.0)
    }
    
    // Shadow optimization - only use complex shadows when not animating
    private var shadowRadius: CGFloat {
        return abs(dragOffset.width) > 5 ? 5 : 10
    }
    
    // Use thumbnail during animations to improve performance
    private var displayImage: UIImage? {
        if abs(dragOffset.width) > 10 {
            return photo.thumbnailImage
        } else {
            return photo.image
        }
    }
    
    var body: some View {
        ZStack {
            // Card content
            VStack {
                if let creationDate = photo.creationDate {
                    Text(dateFormatter.string(from: creationDate))
                        .font(.headline)
                        .padding(.top)
                }
                
                if let image = displayImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(10)
                        .padding()
                        .frame(maxWidth: size.width * 0.85, maxHeight: size.height * 0.7)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(3/4, contentMode: .fit)
                        .cornerRadius(10)
                        .padding()
                        .frame(maxWidth: size.width * 0.85, maxHeight: size.height * 0.7)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        )
                }
            }
            .frame(width: size.width * 0.9, height: size.height * 0.85)
            .background(Color.white)
            .cornerRadius(15)
            .shadow(color: isTopCard ? shadowColor : Color.gray.opacity(0.1), 
                    radius: shadowRadius, x: 0, y: 5)
            
            // Only add overlays for the top card to reduce rendering load
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(overlayOpacity)
                }
                
                // Colored border based on swipe direction
                RoundedRectangle(cornerRadius: 15)
                    .stroke(
                        dragOffset.width > 30 ? Color.green : 
                        dragOffset.width < -30 ? Color.red : 
                        Color.clear,
                        lineWidth: 4
                    )
                    .opacity(overlayOpacity)
            }
        }
        .id(photo.id) // Ensure view is refreshed when photo changes
        // Apply .drawingGroup() for better rendering performance
        .drawingGroup()
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
