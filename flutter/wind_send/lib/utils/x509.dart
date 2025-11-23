import 'dart:io';
import 'package:basic_utils/basic_utils.dart';

/// Parses all domain names from a PEM-formatted X.509 certificate string.
/// Returns domains from SAN (Subject Alternative Names) if present, otherwise falls back to CN (Common Name).
List<String> parseCertificateDomain(String pemString) {
  final X509CertificateData cert = X509Utils.x509CertificateFromPem(pemString);

  final tbs = cert.tbsCertificate;
  if (tbs == null) {
    return const [];
  }

  final Map<String, String?> subject = tbs.subject;
  final String? commonName = subject['2.5.4.3']; // OID 2.5.4.3 is commonName

  final X509CertificateDataExtensions? exts = tbs.extensions;
  final List<String> sanList = exts?.subjectAlternativNames ?? const [];

  final Set<String> result = <String>{};

  for (final san in sanList) {
    final host = _extractHostFromSan(san);
    if (host.isNotEmpty) {
      result.add(host);
    }
  }

  if (result.isEmpty && commonName != null && commonName.isNotEmpty) {
    result.add(commonName);
  }

  return result.toList();
}

/// Extracts hostname from SAN string, supporting formats like:
/// "DNS:example.com", "IP:1.2.3.4", or plain "example.com"
String _extractHostFromSan(String san) {
  String trimPrefix(String str, String prefix) {
    if (str.startsWith(prefix)) {
      return str.substring(prefix.length);
    }
    return str;
  }

  san = trimPrefix(san, 'DNS:');
  san = trimPrefix(san, 'IP:');
  return san;
}

/// Selects the most suitable domain name for TLS connection from a certificate.
/// Selection strategy:
/// 1. Starts from the last domain in the list (reverse order)
/// 2. Skips local domains (localhost, 127.0.0.1, ::1, etc.)
/// 3. Falls back to "localhost" if no suitable domain is found
String selectSniDomain(String pemString) {
  final domains = parseCertificateDomain(pemString);
  if (domains.isEmpty) {
    return 'localhost';
  }

  for (int i = domains.length - 1; i >= 0; i--) {
    final domain = domains[i].toLowerCase().trim();

    if (_isLocalDomain(domain)) {
      continue;
    }

    return domains[i];
  }

  return 'localhost';
}

/// Checks if a domain is a local domain
bool _isLocalDomain(String domain) {
  if (domain.isEmpty) {
    return true;
  }

  final localDomains = [
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
    '0000:0000:0000:0000:0000:0000:0000:0001',
  ];

  if (localDomains.contains(domain)) {
    return true;
  }

  if (domain.startsWith('127.')) {
    return true;
  }

  if (domain.startsWith('::1')) {
    return true;
  }

  if (domain.startsWith('fe80:')) {
    return true;
  }

  final addr = InternetAddress.tryParse(domain);
  if (addr != null && addr.isLoopback) {
    return true;
  }

  return false;
}
