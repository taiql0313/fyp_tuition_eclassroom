import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView wrapper for PayPal approval flow.
/// It watches for redirect to our fake success/cancel URLs and then returns
/// the PayPal order ID (token) back to the caller.
class PayPalWebViewPage extends StatefulWidget {
  final String approvalUrl;

  const PayPalWebViewPage({super.key, required this.approvalUrl});

  @override
  State<PayPalWebViewPage> createState() => _PayPalWebViewPageState();
}

class _PayPalWebViewPageState extends State<PayPalWebViewPage> {
  // These URLs only need to match what we send as return_url/cancel_url.
  static const String _successUrl = 'https://tuition-eclassroom.com/paypal-success';
  static const String _cancelUrl = 'https://tuition-eclassroom.com/paypal-cancel';

  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            // Detect success redirect
            if (url.startsWith(_successUrl)) {
              final uri = Uri.parse(url);
              final orderId = uri.queryParameters['token'];
              Navigator.pop(context, {
                'status': 'success',
                'orderId': orderId,
              });
              return NavigationDecision.prevent;
            }

            // Detect cancel redirect
            if (url.startsWith(_cancelUrl)) {
              Navigator.pop(context, {'status': 'cancel'});
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.approvalUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with PayPal'),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

