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
      } else {
        // Stranica je uspješno učitana, dohvati obračunska mjerna mjesta
        await _extractMeteringPoints();
      }
    }
    // Napomena: Ako smo na /Pocetna, ne radimo ništa jer će onPageFinished 
    // automatski prebaciti na /Ocitanja
  }

  Future<void> _extractMeteringPoints() async {
    // Pričekaj da se stranica potpuno učita i dropdown popuni
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      // JavaScript za dohvaćanje opcija iz select2 dropdown-a
      final String jsCode = '''
        (function() {
          // Prvo pokušaj dohvatiti iz otvorenog dropdown-a
          let options = document.querySelectorAll('.select2-results__option');
          let meteringPoints = [];
          
          if (options.length === 0) {
            // Ako dropdown nije otvoren, pokušaj dohvatiti iz originalnog select elementa
            let selectElement = document.getElementById('omm_select');
            if (selectElement) {
              options = selectElement.options;
              for (let i = 0; i < options.length; i++) {
                if (options[i].value) {
                  meteringPoints.push({
                    text: options[i].text,
                    value: options[i].value
                  });
                }
              }
            }
          } else {
            // Parsiraj podatke iz select2 dropdown-a
            options.forEach(option => {
              let divs = option.querySelectorAll('div > div');
              if (divs.length >= 3) {
                meteringPoints.push({
                  ime: divs[0].textContent.trim(),
                  broj: divs[1].textContent.trim(),
                  adresa: divs[2].textContent.trim()
                });
              }
            });
          }
          
          return JSON.stringify(meteringPoints);
        })();
      ''';
      
      final result = await controller.runJavaScriptReturningResult(jsCode);
      
      if (result != null && result != 'null') {
        // Debug print rezultata
        print('=== OBRAČUNSKA MJERNA MJESTA ===');
        print(result);
        
        // Pokušaj parsirati JSON
        try {
          final String jsonString = result.toString();
          // Ukloni navodnike s početka i kraja ako postoje
          final cleanJson = jsonString.startsWith('"') && jsonString.endsWith('"')
              ? jsonString.substring(1, jsonString.length - 1)
              : jsonString;
          
          print('Cleaned JSON: $cleanJson');
          
          // Zamijeni escape karaktere
          final unescapedJson = cleanJson
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', r'\');
          
          print('Parsed metering points: $unescapedJson');
        } catch (e) {
          print('Error parsing JSON: $e');
        }
        
        print('================================');
      } else {
        print('Nema dostupnih obračunskih mjernih mjesta ili dropdown nije pronađen.');
      }
    } catch (e) {
      print('Greška pri dohvaćanju obračunskih mjernih mjesta: $e');
    }
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