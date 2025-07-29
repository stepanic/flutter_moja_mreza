import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class MojaMrezaWebViewScreen extends StatefulWidget {
  const MojaMrezaWebViewScreen({super.key});

  @override
  State<MojaMrezaWebViewScreen> createState() => _MojaMrezaWebViewScreenState();
}

class _MojaMrezaWebViewScreenState extends State<MojaMrezaWebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasCheckedAuth = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
          },
          onPageFinished: (String url) async {
            setState(() {
              isLoading = false;
            });
            
            // Provjeri autentifikaciju samo jednom
            if (!hasCheckedAuth && url.contains('mojamreza.hep.hr')) {
              hasCheckedAuth = true;
              await _checkAuthenticationStatus(url);
            }
            
            // Ako smo završili na /Pocetna, automatski idi na /Ocitanja
            // (ovo se događa nakon login-a ili ako je korisnik već autentificiran)
            if (url.endsWith('/Pocetna')) {
              await Future.delayed(const Duration(milliseconds: 500));
              await controller.loadRequest(Uri.parse('https://mojamreza.hep.hr/Ocitanja'));
            }
          },
          onWebResourceError: (WebResourceError error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${error.description}'),
                backgroundColor: Colors.red,
              ),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse('https://mojamreza.hep.hr/Ocitanja'));
  }

  Future<void> _checkAuthenticationStatus(String currentUrl) async {
    // Ako smo završili na homepage ili root URL-u nakon pokušaja učitavanja /Ocitanja,
    // znači da nismo autentificirani
    if (currentUrl == 'https://mojamreza.hep.hr/' || 
        currentUrl == 'https://mojamreza.hep.hr') {
      // Preusmjeri na login
      await controller.loadRequest(Uri.parse('https://mojamreza.hep.hr/NiasSignOnRequest'));
    } else if (currentUrl.contains('/Ocitanja')) {
      // Provjeri postoji li tekst koji potvrđuje da su očitanja učitana
      final String? pageContent = await controller.runJavaScriptReturningResult(
        'document.body.innerText'
      ) as String?;
      
      if (pageContent != null && !pageContent.contains('Ovdje možete vidjeti očitanja brojila')) {
        // Ako nema očekivani tekst, vjerojatno smo preusmjereni
        await controller.loadRequest(Uri.parse('https://mojamreza.hep.hr/NiasSignOnRequest'));
      }
    }
    // Napomena: Ako smo na /Pocetna, ne radimo ništa jer će onPageFinished 
    // automatski prebaciti na /Ocitanja
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moja Mreža'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}