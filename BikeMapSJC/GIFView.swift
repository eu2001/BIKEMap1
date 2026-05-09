import SwiftUI
import UIKit
import ImageIO

// MARK: - SwiftUI wrapper

struct GIFView: UIViewRepresentable {
    let name: String
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.setGIF(named: name)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}
}

// MARK: - UIImageView GIF loader

private extension UIImageView {
    func setGIF(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))

            let delay = frameDelay(source: source, index: i)
            duration += delay
        }

        if images.count == 1 {
            image = images[0]
        } else {
            animationImages = images
            animationDuration = duration
            startAnimating()
        }
    }

    private func frameDelay(source: CGImageSource, index: Int) -> Double {
        let defaultDelay = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return defaultDelay
        }
        let delay = (gifProps[kCGImagePropertyGIFUnclampedDelayTime as String]
                  ?? gifProps[kCGImagePropertyGIFDelayTime as String]) as? Double ?? defaultDelay
        return delay > 0.01 ? delay : defaultDelay
    }
}
