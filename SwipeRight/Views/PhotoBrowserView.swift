import SwiftUI
import Photos

struct PhotoBrowserView: View {
    let model: PhotoViewModel
    
    // State for controlling UI
    @State private var isFirstLoad: Bool = true
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                // Title
                Text("Photo Browser")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Progress indicator
                if !model.photoAssets.isEmpty && !model.isBatchComplete {
                    Text(model.progress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // Photo browsing area with swipeable stack
                SwipeablePhotoStack(model: model)
                    .frame(maxHeight: .infinity)
                
                // Instructions - only show when actively browsing
                if model.currentPhoto != nil {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "arrow.left")
                                .foregroundColor(.red)
                            Text("Swipe left to archive")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Swipe right to keep")
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: model.currentPhoto != nil)
                }
            }
        }
        .task {
            if isFirstLoad {
                isFirstLoad = false
                await model.requestPhotoLibraryPermission()
            }
        }
    }
}

// Preview provider
#Preview {
    PhotoBrowserView(model: PhotoViewModel())
} 