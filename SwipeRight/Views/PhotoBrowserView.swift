import SwiftUI
import Photos

struct PhotoBrowserView: View {
    let model: PhotoViewModel
    
    // State for controlling UI
    @State private var isFirstLoad: Bool = true
    @State private var showingInstructions: Bool = false
    
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
                
                // Progress indicator - only show when actively browsing
                if !model.photoAssets.isEmpty && !model.isBatchComplete && model.currentPhoto != nil {
                    Text(model.progress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
                
                // Photo browsing area with swipeable stack
                SwipeablePhotoStack(model: model)
                    .frame(maxHeight: .infinity)
                    .onChange(of: model.currentPhoto) { oldValue, newValue in
                        // Only show instructions when we have a photo to display
                        withAnimation {
                            showingInstructions = newValue != nil
                        }
                    }
                
                // Instructions - only show when actively browsing
                if showingInstructions {
                    instructionsView
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
    
    // Extract the instructions view for better performance
    private var instructionsView: some View {
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
    }
}

// Preview provider
#Preview {
    PhotoBrowserView(model: PhotoViewModel())
} 