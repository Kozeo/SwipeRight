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
                
                // Photo browsing area
                ZStack {
                    // Show current photo
                    if let currentPhoto = model.currentPhoto {
                        PhotoCardView(photo: currentPhoto) { direction in
                            Task {
                                await model.processSwipe(direction)
                            }
                        }
                        .padding(.horizontal, 20)
                    } else if model.isLoading {
                        // Loading state
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.5)
                                .padding()
                            
                            Text("Loading photos...")
                                .font(.headline)
                        }
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
                    } else if model.isBatchComplete {
                        // Batch complete state
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
                                    await model.startNewBatch()
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding(.top)
                        }
                        .transition(.opacity.combined(with: .scale))
                        .animation(.spring(response: 0.5), value: model.isBatchComplete)
                    } else if model.photoAssets.isEmpty && !model.isLoading {
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
                                    await model.startNewBatch()
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