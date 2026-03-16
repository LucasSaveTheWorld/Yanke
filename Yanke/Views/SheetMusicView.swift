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
        // Required for Web Audio API (piano sound synthesis)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.isOpaque = false
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
            body { background: #fff; padding: 12px; font-family: -apple-system, sans-serif; }

            #notation svg { width: 100% !important; height: auto !important; }

            /* Player bar */
            #player {
              position: fixed;
              bottom: 0; left: 0; right: 0;
              background: #f9f9f9;
              border-top: 1px solid #e0e0e0;
              padding: 10px 16px;
              display: flex;
              align-items: center;
              gap: 10px;
            }
            .abcjs-midi-start.abcjs-pushed { background: #4f46e5; color: white; }
            .abcjs-btn {
              font-size: 20px;
              background: none; border: none;
              cursor: pointer; padding: 4px 8px;
              border-radius: 8px;
            }
            .abcjs-btn:active { background: #e0e0e0; }
            .abcjs-midi-progress-indicator {
              flex: 1; height: 4px; background: #4f46e5;
              border-radius: 2px;
            }
            .abcjs-midi-progress {
              flex: 1; height: 4px; background: #e0e0e0;
              border-radius: 2px; overflow: hidden;
            }
            .abcjs-loading { color: #999; font-size: 13px; }

            /* Pad sheet above fixed player */
            body { padding-bottom: 80px; }

            .error { color: red; font-size: 12px; padding: 8px; }
          </style>
        </head>
        <body>
          <div id="notation"></div>
          <div id="player"></div>

          <!-- Full abcjs bundle includes synth/audio engine -->
          <script src="https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-min.js"></script>
          <script>
            const abc = `\(escaped)`;

            // 1. Render notation
            const visualObj = ABCJS.renderAbc("notation", abc, {
              responsive: "resize",
              staffwidth: window.innerWidth - 24,
              scale: 1.4,
              add_classes: true,
              paddingtop: 10,
              paddingbottom: 10,
              paddingright: 10,
              paddingleft: 10,
            });

            // 2. Set up piano playback via SynthController
            if (ABCJS.synth.supportsAudio()) {
              const synthControl = new ABCJS.synth.SynthController();
              synthControl.load("#player", null, {
                displayLoop: false,
                displayRestart: true,
                displayPlay: true,
                displayProgress: true,
                displayWarp: false,
              });

              synthControl.setTune(visualObj[0], false, {
                // General MIDI program 0 = Acoustic Grand Piano
                midiTranspose: 0,
                chordsOff: false,
                voicesOff: false,
              }).then(() => {
                console.log("Piano audio ready");
              }).catch(e => {
                document.getElementById("player").innerHTML =
                  '<div class="error">Audio init failed: ' + e + '</div>';
              });
            } else {
              document.getElementById("player").innerHTML =
                '<div class="error">Audio not supported in this browser</div>';
            }
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
