import SwiftUI
import WebKit

struct SheetMusicView: View {
    let notes: [Note]
    let fileName: String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(notes.count) notes detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)

            Divider()

            // Sheet music
            SheetMusicWebView(abc: ABCConverter.convert(notes, title: fileName))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .background(Color.white)
    }
}

// MARK: - WKWebView wrapper

struct SheetMusicWebView: UIViewRepresentable {
    let abc: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.isOpaque = false
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let escaped = abc
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { background: white; padding: 12px; font-family: -apple-system, sans-serif; }
            #notation svg { width: 100% !important; height: auto !important; }
            .error { color: red; font-size: 12px; padding: 8px; }
          </style>
        </head>
        <body>
          <div id="notation"></div>
          <script src="https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.js"></script>
          <script>
            try {
              ABCJS.renderAbc("notation", `\(escaped)`, {
                responsive: "resize",
                paddingtop: 10,
                paddingbottom: 10,
                paddingright: 10,
                paddingleft: 10,
                staffwidth: window.innerWidth - 24,
                scale: 1.4,
                add_classes: true,
              });
            } catch(e) {
              document.getElementById("notation").innerHTML =
                '<div class="error">Notation error: ' + e.message + '</div>';
            }
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
