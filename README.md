# flutter_moja_mreza

Flutter plugin za pristup HEP-ovom portalu Moja Mreža.

## Funkcionalnosti

- Automatska provjera autentifikacije korisnika
- Prvo pokušava otvoriti stranicu s očitanjima (`/Ocitanja`)
- Ako korisnik nije autentificiran, automatski preusmjerava na login (`/NiasSignOnRequest`)
- Na mobilnim platformama (Android/iOS): prikazuje se u WebView-u unutar aplikacije
- Na web platformi: otvara se u novom tabu

### Logika autentifikacije
1. WebView prvo pokušava učitati `https://mojamreza.hep.hr/Ocitanja`
2. Ako je korisnik autentificiran, prikazat će se stranica s tekstom "Ovdje možete vidjeti očitanja brojila."
3. Ako nije autentificiran, bit će preusmjeren na homepage ili login stranicu
4. Aplikacija automatski detektira preusmjeravanje i otvara login stranicu

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

