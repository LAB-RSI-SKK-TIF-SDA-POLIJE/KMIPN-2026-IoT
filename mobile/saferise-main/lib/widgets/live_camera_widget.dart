import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Widget yang menampilkan live MJPEG stream dari Raspberry Pi.
/// Menerima [piIp] langsung dari parent, auto-connect ke stream.
class LiveCameraWidget extends StatefulWidget {
  const LiveCameraWidget({
    super.key,
    required this.cameraId,
    required this.cameraName,
    required this.piIp,
    this.streamPort = 8080,
    this.height = 180,
  });

  final String cameraId;
  final String cameraName;
  final String piIp;
  final int streamPort;
  final double height;

  @override
  State<LiveCameraWidget> createState() => _LiveCameraWidgetState();
}

class _LiveCameraWidgetState extends State<LiveCameraWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  String get _streamUrl => 'http://${widget.piIp}:${widget.streamPort}/stream';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(covariant LiveCameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piIp != widget.piIp) {
      _initWebView();
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_streamUrl));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          children: [
            // WebView
            if (!_hasError)
              WebViewWidget(controller: _controller)
            else
              _buildPlaceholder(),

            // Label kamera (atas kiri)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      widget.cameraName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Live indicator (atas kanan)
            if (!_hasError)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? Colors.orange.withOpacity(0.8)
                        : Colors.green.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isLoading ? 'CONNECTING...' : 'LIVE',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading overlay
            if (_isLoading && !_hasError)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Color(0xFF6B7280), size: 36),
            const SizedBox(height: 8),
            const Text(
              'Koneksi stream gagal',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${widget.piIp}:${widget.streamPort}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}