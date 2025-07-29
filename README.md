# flutter_moja_mreza

Flutter plugin za pristup HEP-ovom portalu Moja Mreža.

## Funkcionalnosti

- Otvaranje https://mojamreza.hep.hr/ portala
- Na mobilnim platformama (Android/iOS): prikazuje se u WebView-u unutar aplikacije
- Na web platformi: otvara se u novom tabu

## Ograničenja

### Web platforma
Na web platformi postoje CORS (Cross-Origin Resource Sharing) ograničenja koja onemogućavaju:
- Dohvaćanje HTML sadržaja sa mojamreza.hep.hr
- JavaScript interakciju s učitanom stranicom
- Čitanje podataka iz iframe-a

Moguća rješenja za web:
1. **Proxy server**: Backend servis koji dohvaća podatke i proslijedi ih aplikaciji
2. **Browser ekstenzija**: Može zaobići CORS ali zahtijeva instalaciju
3. **Fokus na mobilne platforme**: Android i iOS nemaju CORS ograničenja

### Mobilne platforme
Na Android i iOS platformama možete:
- Prikazati web stranicu u WebView-u
- Izvršavati JavaScript na stranici
- Dohvatiti HTML sadržaj
- Komunicirati između Flutter aplikacije i web stranice

## Primjer korištenja

```dart
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';

final _flutterMojaMrezaPlugin = FlutterMojaMreza();

// Otvori Moja Mreža portal
await _flutterMojaMrezaPlugin.openMojaMreza(context);
```

