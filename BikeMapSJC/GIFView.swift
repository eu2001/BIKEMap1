import SwiftUI
import WebKit

struct GIFView: UIViewRepresentable {
    let name: String
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .white
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
            let html = """
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              html, body { width: 100%; height: 100%; background: white; }
              img { width: 100%; height: 100%; object-fit: fill; display: block; }
            </style>
            </head>
            <body>
              <img src="\(url.absoluteString)">
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: url)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
