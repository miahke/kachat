import '../payments/payment_hub.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/site_links.dart';
import '../../core/theme/nym_colors.dart';
import '../../core/theme/nym_metrics.dart';
import '../../state/app_state.dart';
import '../../state/nostr_controller.dart';
import '../i18n/i18n.dart';
import '../share/share_actions.dart';
import '../share/share_sheet.dart';
import '../identity/modal_chrome.dart';
import 'settings_widgets.dart';
import '../../widgets/common/nym_sheet.dart';
import '../../widgets/common/dialog_button.dart';
import '../../widgets/nym_icons.dart';

/// Bundled fallback version, shown until the live version resolves; keep in sync with `NYMCHAT_VERSION` at release.
const String kAboutVersion = 'v3.75.545';

const String kAboutCopyright = 'Based on Nymchat by 21 Million LLC';

/// About modal: installed version header, links and the contact form.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key, this.initialTopic, this.initialMessage});

  /// Pre-selected contact topic, one of the [FormSelect] options; null keeps 'General feedback'.
  final String? initialTopic;

  /// Pre-filled contact message; null leaves it empty.
  final String? initialMessage;

  static Future<void> open(
    BuildContext context, {
    String? initialTopic,
    String? initialMessage,
  }) {
    return showNymSheet<void>(
      context,
      (_) => AboutScreen(
        initialTopic: initialTopic,
        initialMessage: initialMessage,
      ),
      barrierColor: Colors.black.withValues(alpha: 0.7),
    );
  }

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  final _messageController = TextEditingController();
  String _topic = 'General feedback';
  final List<TapGestureRecognizer> _recognizers = [];

  /// Contact status line; [_statusOk] picks success vs error color.
  String? _status;
  bool _statusOk = false;
  bool _sending = false;

  String _version = kAboutVersion;

  @override
  void initState() {
    super.initState();
    // Pre-fill for a spam false-positive report.
    final topic = widget.initialTopic;
    if (topic != null && topic.isNotEmpty) _topic = topic;
    final msg = widget.initialMessage;
    if (msg != null && msg.isNotEmpty) _messageController.text = msg;
    // Keeps the bundled fallback on error.
    _loadInstalledVersion();
    // No-ops off Android.
  }

  Future<void> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {}
  }

  @override
  void dispose() {
    _messageController.dispose();
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nym;
    // Shift up by the keyboard inset and cap the height so the contact field isn't hidden.
    final viewInsets = MediaQuery.of(context).viewInsets;
    final visibleHeight =
        MediaQuery.of(context).size.height - viewInsets.bottom;
    final body = Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(c),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _description(c),
                    _links(c),
                    _shareAppRow(c),
                    _license(c),
                    const SizedBox(height: 20),
                    Container(height: 1, color: c.glassBorder),
                    const SizedBox(height: 20),
                    Text(
                      tr('Contact the developer'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        'Send feedback, a question, or a bug report. '
                        'Your message is delivered as an encrypted '
                        'private message to the Nymchat developer.',
                      ),
                      style: TextStyle(
                        color: c.textDim,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormGroup(
                      label: tr('Topic'),
                      child: FormSelect<String>(
                        value: _topic,
                        items: [
                          (
                            value: 'General feedback',
                            label: tr('General feedback'),
                          ),
                          (value: 'Bug report', label: tr('Bug report')),
                          (
                            value: 'Feature request',
                            label: tr('Feature request'),
                          ),
                          (value: 'Question', label: tr('Question')),
                          (
                            value: 'Spam false positive',
                            label: tr('Spam false positive'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _topic = v),
                      ),
                    ),
                    FormGroup(label: tr('Message'), child: _messageBox()),
                    if (_status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _status!,
                          style: TextStyle(
                            color: _statusOk ? c.secondary : c.danger,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    const InformationPayments(),
                  ],
                ),
              ),
            ),
            _actions(c),
          ],
        ),
        ModalChrome.closeChip(c, () => Navigator.of(context).pop()),
      ],
    );
    return NymDiscardGuard(
      isDirty: () => _messageController.text.trim().isNotEmpty,
      child: nymSheetOr(
        context,
        body,
        (body) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.bgSecondary,
                      borderRadius: NymRadius.rxl,
                      border: Border.all(color: c.glassBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            (visibleHeight - 40).clamp(200.0, visibleHeight) *
                            0.98,
                      ),
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(NymColors c) {
    // Right padding keeps the title clear of the floating close chip.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 56, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.glassBorder)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        children: [
          Text(
            'kachat',
            style: TextStyle(
              color: c.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              _version,
              style: TextStyle(
                color: c.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _description(NymColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 16),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: tr('A decentralized, pseudonymous chat built on the '),
            ),
            _linkSpan(c, 'Nostr', 'https://nostr.com'),
            TextSpan(
              text: tr(
                " protocol. Inspired by and bridged with Jack Dorsey's ",
              ),
            ),
            _linkSpan(c, 'Bitchat', 'https://bitchat.free'),
            const TextSpan(text: '.'),
          ],
        ),
        style: TextStyle(color: c.textDim, fontSize: 13, height: 1.6),
      ),
    );
  }

  Widget _links(NymColors c) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _link(c, tr('Docs'), kDocsUrl),
        _link(c, 'GitHub', kGithubUrl),
        _link(c, tr('Terms of Service'), kTermsUrl),
        _link(c, tr('Privacy Policy'), kPrivacyUrl),
        _link(c, 'DMCA', kDmcaUrl),
      ],
    );
  }

  Widget _shareAppRow(NymColors c) {
    final launch = ref.watch(appShareLauncherProvider);
    if (launch == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ShareActionRow(
        key: const ValueKey('about-share-app'),
        svg: NymIcons.shareNodes,
        label: tr('Share Nymchat app').replaceAll('Nymchat', 'kachat'),
        onTap: () => unawaited(launch(context)),
      ),
    );
  }

  Widget _license(NymColors c) {
    return Padding(
      key: const ValueKey('about-license'),
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _creditLink(c, kAboutCopyright, 'https://github.com/Spl0itable/NYM'),
          Text(' · ', style: TextStyle(color: c.textDim, fontSize: 12)),
          _creditLink(c, 'Modified kachat · AGPL-3.0', kLicenseUrl),
        ],
      ),
    );
  }

  Widget _creditLink(NymColors c, String text, String url) {
    return Semantics(
      link: true,
      linkUrl: Uri.parse(url),
      child: InkWell(
        onTap: () => _openLink(url),
        child: Text(text, style: TextStyle(color: c.secondary, fontSize: 12)),
      ),
    );
  }

  /// Contact textarea, max 2000 chars with no counter.
  Widget _messageBox() {
    return FormInput(
      controller: _messageController,
      hint: tr('Write your message...'),
      maxLines: 4,
      maxLength: 2000,
    );
  }

  Widget _actions(NymColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.glassBorder)),
      ),
      child: DialogActions(
        children: [
          DialogButton.secondary(
            label: tr('Close'),
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            label: _sending ? tr('SENDING...') : tr('SEND MESSAGE'),
            onTap: _sending ? null : _sendContact,
          ),
        ],
      ),
    );
  }

  Widget _link(NymColors c, String text, String url, {double size = 12}) {
    return GestureDetector(
      onTap: () => _openLink(url),
      child: Text(
        text,
        style: TextStyle(
          color: c.secondary,
          fontSize: size,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  TextSpan _linkSpan(NymColors c, String text, String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _openLink(url);
    _recognizers.add(recognizer);
    return TextSpan(
      text: text,
      style: TextStyle(color: c.secondary),
      recognizer: recognizer,
    );
  }

  /// Opens [url] externally; every link is absolute.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort; a missing handler no-ops.
    }
  }

  /// Sends the contact message as an encrypted PM to the verified developer, clearing the field only on success.
  Future<void> _sendContact() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _status = tr('Please enter a message.');
        _statusOk = false;
      });
      return;
    }
    final connected = ref.read(appStateProvider).connectedRelays > 0;
    if (!connected) {
      setState(() {
        _status = tr('Not connected to relay. Try again once connected.');
        _statusOk = false;
      });
      return;
    }

    setState(() {
      _sending = true;
      _status = null;
    });

    // Gift-wrapped to the developer as `[Nymchat contact — <topic>]\n\n<message>`.
    final body = '[Nymchat contact — $_topic]\n\n$text';
    var ok = false;
    try {
      ok = await ref.read(nostrControllerProvider).sendContactMessage(body);
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _status = tr('Message sent. Thanks for reaching out!');
        _statusOk = true;
        _messageController.clear();
      } else {
        _status = tr('Failed to send. Please try again.');
        _statusOk = false;
      }
    });
  }
}
