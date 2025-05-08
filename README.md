# SwipeRight Photo Browser

A SwiftUI app that allows users to swipe through random photos from their camera roll with smooth animations and visual indicators.

## Features

- Browse through randomly selected photos from your camera roll
- Process photos in batches of 10 for efficient organization
- Swipe right to keep photos (green halo effect)
- Swipe left to archive photos (red text)
- View photo date metadata
- Smooth swipe animations and transitions
- Batch completion feedback
- Optimized memory management (only one photo loaded at a time)
- Proper permission handling for photo library access

## Architecture

This app is built using the MVVM (Model-View-ViewModel) pattern:

- **Models**: Represent the data structure (PhotoModel)
- **ViewModels**: Handle business logic and data processing (PhotoViewModel)
- **Views**: Display the UI elements and handle user interactions (PhotoBrowserView, PhotoCardView)

## Performance Optimizations

- Asynchronous photo loading to prevent main thread blocking
- On-demand image loading (only load current image into memory)
- Proper memory management to prevent crashes
- Efficient batch processing

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Getting Started

1. Clone the repository
2. Open the project in Xcode
3. Build and run on a device or simulator
4. Grant photo library access when prompted

## Implementation Details

- Uses PhotoKit for photo library access
- Implements modern SwiftUI features and best practices
- Uses the Observation framework for reactive updates
- Handles permissions properly with clear user messaging
- Follows Swift's modern concurrency model 