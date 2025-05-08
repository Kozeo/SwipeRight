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
    
    var body: some View {
        ZStack {
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
            .shadow(color: isTopCard ? shadowColor : Color.gray.opacity(0.1), 
                    radius: 10, x: 0, y: 5)
            .overlay(
                ZStack {
                    // Keep overlay (green)
                    if dragOffset.width > 30 {
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
                            .opacity(overlayOpacity)
                    }
                    
                    // Archive overlay (red)
                    if dragOffset.width < -30 {
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
                            .opacity(overlayOpacity)
                    }
                }
            )
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
    
    return PhotoCardView(
        photo: photo,
        size: CGSize(width: 350, height: 500),
        dragOffset: CGSize.zero,
        onSwiped: { _ in },
        isTopCard: true
    )
} 
