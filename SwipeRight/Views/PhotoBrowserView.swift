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
                
                // Photo browsing area
                ZStack {
                    // Show current photo
                    if let currentPhoto = model.currentPhoto {
                        PhotoCardView(photo: currentPhoto) { direction in
                            model.processSwipe(direction)
                        }
                        .padding(.horizontal, 20)
                    } else if model.isLoading {
                        // Loading state
                        ProgressView("Loading photos...")
                            .progressViewStyle(CircularProgressViewStyle())
                    } else if let error = model.error {
                        // Error state
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                                .padding()
                            
                            Text(error)
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
                    } else if model.photos.isEmpty {
                        // No photos state
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
                                    await model.resetPhotos()
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Instructions
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
                    
                    if !model.hasMorePhotos && !model.photos.isEmpty {
                        Button("Start Over") {
                            Task {
                                await model.resetPhotos()
                            }
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                    }
                }
                .padding(.bottom)
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