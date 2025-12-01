import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:basic_utils/basic_utils.dart';
import '../../language.dart';
import '../../device.dart';
import '../../utils/x509.dart';

class CertificateDetailPage extends StatefulWidget {
  final Device device;
  final Function(String) onCertificateChanged;

  const CertificateDetailPage({
    super.key,
    required this.device,
    required this.onCertificateChanged,
  });

  @override
  State<CertificateDetailPage> createState() => _CertificateDetailPageState();
}

class _CertificateDetailPageState extends State<CertificateDetailPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _certificateController;
  X509CertificateData? _parsedCertificate;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _certificateController = TextEditingController(
      text: widget.device.trustedCertificate,
    );
    _parseCertificate();
  }

  @override
  void dispose() {
    _certificateController.dispose();
    super.dispose();
  }

  void _parseCertificate() {
    setState(() {
      _parseError = null;
      _parsedCertificate = null;

      final certText = _certificateController.text.trim();
      if (certText.isEmpty) {
        return;
      }

      try {
        _parsedCertificate = X509Utils.x509CertificateFromPem(certText);
      } catch (e) {
        _parseError = e.toString();
      }
    });
  }

  void _saveCertificate() {
    if (_formKey.currentState?.validate() ?? false) {
      final newCert = _certificateController.text.trim();
      widget.onCertificateChanged(newCert);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.trustedCertificate, [])),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveCertificate,
            tooltip: context.formatString(AppLocale.save, []),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCertificateInput(context),
          const SizedBox(height: 24),
          if (_parsedCertificate != null) _buildCertificateInfo(context),
          if (_parseError != null) _buildErrorInfo(context),
        ],
      ),
    );
  }

  Widget _buildCertificateInput(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.formatString(AppLocale.certificate, []),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _parseCertificate,
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  label: Text(context.formatString(AppLocale.parse, [])),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _certificateController,
                maxLines: 10,
                minLines: 5,
                decoration: InputDecoration(
                  hintText: context.formatString(
                    AppLocale.trustedCertificateHint,
                    [],
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: Device.certificateAuthorityValidator(context),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorInfo(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  context.formatString(AppLocale.parseError, []),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _parseError ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateInfo(BuildContext context) {
    final cert = _parsedCertificate!;
    final tbs = cert.tbsCertificate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.formatString(AppLocale.certificateInfo, []),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              context,
              Icons.fingerprint_outlined,
              context.formatString(AppLocale.serialNumber, []),
              tbs?.serialNumber.toString() ?? '-',
            ),
            const Divider(height: 24),
            if (tbs != null) ...[
              _buildInfoRow(
                context,
                Icons.business_outlined,
                context.formatString(AppLocale.issuer, []),
                _formatSubject(tbs.issuer),
              ),
              const Divider(height: 24),
              _buildInfoRow(
                context,
                Icons.account_circle_outlined,
                context.formatString(AppLocale.subject, []),
                _formatSubject(tbs.subject),
              ),
              const Divider(height: 24),
            ],
            _buildInfoRow(
              context,
              Icons.calendar_today_outlined,
              context.formatString(AppLocale.validity, []),
              _formatValidity(tbs),
            ),
            const Divider(height: 24),
            _buildInfoRow(
              context,
              Icons.verified_user_outlined,
              context.formatString(AppLocale.signatureAlgorithm, []),
              cert.signatureAlgorithm,
            ),
            const Divider(height: 24),
            _buildDomainInfo(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDomainInfo(BuildContext context) {
    final certText = _certificateController.text.trim();
    final domains = parseCertificateDomain(certText);
    final sniDomain = selectSniDomain(certText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              context.formatString(AppLocale.domains, []),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (domains.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              context.formatString(AppLocale.noDomains, []),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: domains
                  .map(
                    (domain) => Tooltip(
                      message: domain,
                      child: Chip(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(domain, overflow: TextOverflow.ellipsis),
                        ),
                        avatar: domain == sniDomain
                            ? Icon(
                                Icons.star,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (domains.isNotEmpty && sniDomain.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 8),
            child: Text(
              '${context.formatString(AppLocale.sniDomain, [])}: $sniDomain',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  String _formatSubject(Map<String, String?>? subject) {
    if (subject == null || subject.isEmpty) {
      return '-';
    }

    final Map<String, String> oidNames = {
      '2.5.4.3': 'CN',
      '2.5.4.6': 'C',
      '2.5.4.7': 'L',
      '2.5.4.8': 'ST',
      '2.5.4.10': 'O',
      '2.5.4.11': 'OU',
    };

    final parts = <String>[];
    subject.forEach((oid, value) {
      if (value != null && value.isNotEmpty) {
        final name = oidNames[oid] ?? oid;
        parts.add('$name=$value');
      }
    });

    return parts.isEmpty ? '-' : parts.join(', ');
  }

  String _formatValidity(TbsCertificate? tbs) {
    if (tbs == null) {
      return '-';
    }

    try {
      final validity = tbs.validity;
      final notBefore = validity.notBefore;
      final notAfter = validity.notAfter;

      final now = DateTime.now();
      String status = '';

      if (now.isBefore(notBefore)) {
        status = ' (Not yet valid)';
      } else if (now.isAfter(notAfter)) {
        status = ' (Expired)';
      } else {
        status = ' (Valid)';
      }

      return '${_formatDateTime(notBefore)} - ${_formatDateTime(notAfter)}$status';
    } catch (e) {
      return '-';
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
