/// Central place to configure the backend address.
///
/// Backend is exposed publicly via Cloudflare Tunnel at call.sofmebel.uz,
/// so this single HTTPS URL works from any device — real phones, emulators,
/// anywhere with internet access. No LAN IP or 10.0.2.2 needed.
class ApiConfig {
  static const String baseUrl = 'https://call.sofmebel.uz';

  // Socket.IO uses the same host, just without any REST path.
  static const String socketUrl = baseUrl;
}
