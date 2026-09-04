import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/models/chat_message.dart';

const _kBlue = Color(0xFF329AD6);
const _kDarkBlue = Color(0xFF1A6FA8);
const _kBg = Color(0xFFF0F6FF);

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final int index;
  final void Function(int)? onRetryMetaRoom;
  final VoidCallback? onNewSession;

  const MessageBubble({
    super.key,
    required this.message,
    required this.index,
    this.onRetryMetaRoom,
    this.onNewSession,
  });

  @override
  Widget build(BuildContext context) {
    if (message.text == '__session_end__') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          children: [
            // Divider with label
            Row(children: [
              const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Flow completed',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
              const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
            ]),
            const SizedBox(height: 14),
            // Session end card
            Builder(builder: (context) {
              final cs = Theme.of(context).colorScheme;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 12, offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                    ),
                    child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text('Application Submitted',
                      style: TextStyle(color: cs.onSurface, fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Your session has ended successfully.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onNewSession,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Start New Session',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ),
      );
    }

    if (message.metaRoom != null) return _buildMetaRoomCard(context);

    final isUser = message.from == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _BotAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.imageUrl != null) _buildImageBubble(context),
                if (message.card == null && message.imageUrl == null)
                  _buildBotBubble(context, isUser),
                if (message.card != null) _buildCard(context, isUser),
                Padding(
                  padding: EdgeInsets.only(top: 3, left: isUser ? 0 : 4, right: isUser ? 4 : 0),
                  child: Text(message.time,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  // Unified bubble: text + optional chart + optional table, all in one container
  Widget _buildBotBubble(BuildContext context, bool isUser) {
    final cs = Theme.of(context).colorScheme;
    final screenW = MediaQuery.of(context).size.width;
    final hasExtra = !isUser && (message.chartImage != null || message.tableHtml != null);
    // Wide enough to show table/chart when present, otherwise normal chat width
    final maxW = hasExtra ? screenW * 0.76 : screenW * 0.76;

    final hasText = message.text.isNotEmpty;
    final hasFile = message.fileName != null;
    if (!hasText && !hasFile && !hasExtra) return const SizedBox.shrink();

    return Container(
      constraints: BoxConstraints(maxWidth: maxW),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: isUser ? cs.secondary : cs.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: isUser
                ? cs.secondary.withValues(alpha: 0.3)
                : cs.onSurface.withValues(alpha: 0.06),
            blurRadius: isUser ? 10 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasText || hasFile)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasText)
                    Text(message.text,
                        style: TextStyle(
                            color: isUser ? Colors.white : cs.onSurface,
                            fontSize: 14,
                            height: 1.55)),
                  if (hasFile)
                    Row(children: [
                      Icon(Icons.attach_file,
                          color: isUser ? Colors.white70 : const Color(0xFF64748B), size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(message.fileName!,
                            style: TextStyle(
                                color: isUser ? Colors.white70 : const Color(0xFF64748B),
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                ],
              ),
            ),
          if (!isUser && message.chartImage != null) _buildChartImage(context),
          if (!isUser && message.tableHtml != null) _buildHtmlTable(context),
          if (!isUser && message.csvData != null) _buildCsvTable(context),
        ],
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.62;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      constraints: BoxConstraints(maxWidth: maxW),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _CachedBase64Image(base64: message.imageUrl!),
      ),
    );
  }

  Widget _buildCard(BuildContext context, bool isUser) {
    final cs = Theme.of(context).colorScheme;
    const maxW = 260.0;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        color: isUser ? cs.secondary : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isUser ? Colors.white.withValues(alpha: 0.2) : cs.onSurface.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: isUser ? Colors.white.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.1))),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_rounded,
                  size: 13,
                  color: isUser ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF16A34A)),
              const SizedBox(width: 5),
              Text(message.text,
                  style: TextStyle(
                      color: isUser ? Colors.white : cs.onSurface,
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          ...message.card!.map((row) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text('${row['label']}',
                      style: TextStyle(
                          color: isUser ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
                          fontSize: 11)),
                ),
                Expanded(
                  child: Text(row['value'] ?? '',
                      style: TextStyle(
                          color: isUser ? Colors.white : cs.onSurface,
                          fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildChartImage(BuildContext context) {
    Uint8List bytes;
    try {
      bytes = base64Decode(message.chartImage!);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => _showFullScreenImage(context, bytes),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(18),
        ),
        child: Image.memory(
          bytes,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => _FullScreenImageViewer(bytes: bytes),
    ));
  }

  Widget _buildHtmlTable(BuildContext context) {
    final html = message.tableHtml!;
    final headerMatches = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true).allMatches(html);
    final headers = headerMatches.map((m) => _stripTags(m.group(1) ?? '')).toList();
    final rowMatches = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html).skip(1);
    final rows = rowMatches.map((r) {
      return RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(r.group(1) ?? '')
          .map((m) => _stripTags(m.group(1) ?? ''))
          .toList();
    }).where((r) => r.isNotEmpty).toList();
    if (headers.isEmpty) return const SizedBox.shrink();

    const hPad = 10.0;
    const fontSize = 11.0;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: headers.asMap().entries.map((e) => Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    border: Border(
                      right: e.key < headers.length - 1
                          ? const BorderSide(color: Color(0xFF1976D2), width: 1)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(e.value,
                      style: const TextStyle(
                          color: Colors.white, fontSize: fontSize,
                          fontWeight: FontWeight.w700)),
                ),
              )).toList(),
            ),
          ),
          // Data rows
          ...rows.asMap().entries.map((e) {
            final rowColor = e.key.isEven ? const Color(0xFFF8FAFC) : Colors.white;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(headers.length, (ci) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: hPad, vertical: 7),
                    decoration: BoxDecoration(
                      color: rowColor,
                      border: Border(
                        top: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                        right: ci < headers.length - 1
                            ? const BorderSide(color: Color(0xFFE2E8F0), width: 1)
                            : BorderSide.none,
                      ),
                    ),
                    child: Text(
                        ci < e.value.length ? e.value[ci] : '',
                        style: const TextStyle(
                            color: Color(0xFF1E293B), fontSize: fontSize)),
                  ),
                )),
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  Widget _buildCsvTable(BuildContext context) {
    final csv = message.csvData!;
    final lines = csv.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return const SizedBox.shrink();
    final allHeaders = lines.first.split(',').map((h) => h.trim()).toList();
    final rows = lines.skip(1).map((l) => l.split(',').map((c) => c.trim()).toList()).toList();
    final rowCount = rows.length;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(10),
        bottomRight: Radius.circular(10),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFC7D7E8)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Excel-style green header bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(0xFF1D6F42),
              child: Row(
                children: [
                  const Icon(Icons.table_chart_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('TB_Statement_6months.csv',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  GestureDetector(
                    onTap: () => _downloadCsv(context, csv),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_rounded, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Download', style: TextStyle(color: Colors.white, fontSize: 11,
                            fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            // ── Scrollable table ──
            SizedBox(
              height: 240,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    border: TableBorder(
                      verticalInside: const BorderSide(color: Color(0xFFE2E8F0)),
                      horizontalInside: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    children: [
                      // Sticky-style header (dark green)
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFF217346)),
                        children: allHeaders.map((h) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: Text(h.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 11,
                                  fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                        )).toList(),
                      ),
                      // Data rows
                      ...rows.asMap().entries.map((e) {
                        final isEven = e.key.isEven;
                        return TableRow(
                          decoration: BoxDecoration(
                              color: isEven ? const Color(0xFFF0F7F0) : Colors.white),
                          children: List.generate(allHeaders.length, (ci) {
                            final cell = ci < e.value.length ? e.value[ci] : '';
                            Color textColor = const Color(0xFF1E293B);
                            FontWeight fw = FontWeight.normal;
                            if (cell == 'CREDIT') { textColor = const Color(0xFF16A34A); fw = FontWeight.w700; }
                            if (cell == 'DEBIT')  { textColor = const Color(0xFFDC2626); fw = FontWeight.w700; }
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text(cell, style: TextStyle(fontSize: 11.5,
                                  color: textColor, fontWeight: fw),
                                  overflow: TextOverflow.ellipsis),
                            );
                          }),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            // ── Footer ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: const Color(0xFFF1F5F9),
              child: Text('$rowCount transactions',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  void _downloadCsv(BuildContext context, String csv) {
    // Wire up share_plus: Share.shareXFiles([XFile.fromData(...)]) if needed.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download: wire up share_plus to save CSV')),
    );
  }

  Widget _buildMetaRoomCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSkeleton = message.metaRoom == 'qr' && message.metaRoomPhase == 'skeleton';
    final isQrReady  = message.metaRoom == 'qr' && message.metaRoomPhase == 'ready';
    final isAuth     = message.metaRoom == 'authenticated';
    final isError    = message.metaRoom == 'error';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BotAvatar(),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18), topRight: Radius.circular(18),
                bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 4, offset: const Offset(0, 1)),
                BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 0, spreadRadius: 1),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE0F0FB), Color(0xFFDBEAFE)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded,
                        color: Color(0xFF329AD6), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      isSkeleton ? 'Generating QR Code…' :
                      isQrReady  ? 'Scan to Login' :
                      isAuth     ? 'Meta Room' : 'Meta Room',
                      style: TextStyle(color: cs.onSurface,
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      isSkeleton ? 'Setting up secure session' :
                      isQrReady  ? 'Open BharatMeta app & scan' :
                      isAuth     ? 'Session verified' : 'Error',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),

                // ── QR state ──
                if (isSkeleton || isQrReady) _buildQrSection(context, isSkeleton),

                // ── Authenticated ──
                if (isAuth) _buildAuthenticated(context),

                // ── Error ──
                if (isError) _buildError(context),

                const SizedBox(height: 6),
                Text(message.time,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Skeleton SVG + real QR — matches Angular mr-qr-skeleton / mr-qr-frame
  Widget _buildQrSection(BuildContext context, bool isSkeleton) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: isSkeleton
              ? _buildSkeletonSvg()
              : _buildQrFrame(context),
        ),
        const SizedBox(height: 8),
        // Poll row
        Row(children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFF329AD6),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isSkeleton ? 'Generating secure QR code…' : 'Waiting for scan…',
            style: const TextStyle(color: Color(0xFF64748B),
                fontSize: 11.5, fontStyle: FontStyle.italic),
          ),
        ]),
      ],
    );
  }

  // Pixel-grid skeleton matching Angular SVG exactly
  Widget _buildSkeletonSvg() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200, height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
          boxShadow: [BoxShadow(color: const Color(0xFF329AD6).withValues(alpha: 0.1), blurRadius: 12)],
        ),
        child: const _SkeletonQr(),
      ),
    );
  }

  Widget _buildQrFrame(BuildContext context) {
    return Container(
      width: 200, height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [BoxShadow(color: const Color(0xFF329AD6).withValues(alpha: 0.1), blurRadius: 12)],
      ),
      clipBehavior: Clip.antiAlias,
      child: QrImageView(
        data: message.metaRoomQrUrl!,
        version: QrVersions.auto,
        size: 200,
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) => _buildSkeletonSvg();

  Widget _buildAuthenticated(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = message.metaRoomSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Blurred QR + green overlay — matches Angular mr-auth-frame
        if (message.metaRoomQrUrl != null)
          Center(
            child: Stack(
              children: [
                // Blurred QR behind
                Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                    child: Transform.scale(
                      scale: 1.05,
                      child: QrImageView(
                        data: message.metaRoomQrUrl!,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF16A34A),
                            boxShadow: [BoxShadow(
                              color: const Color(0xFF16A34A).withValues(alpha: 0.4),
                              blurRadius: 16,
                            )],
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(height: 8),
                        const Text('Logged In',
                            style: TextStyle(fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Center(
            child: Column(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16A34A),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.4),
                      blurRadius: 16,
                    )],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                const Text('Logged In',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
              ],
            ),
          ),
        if (session != null) ...[
          const SizedBox(height: 10),
          // Info card — name + session
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _mrInfoRow('Name', session['name'] ?? ''),
                _mrInfoRow('Session', session['sessionId'] ?? '', isLast: true, small: true),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _mrInfoRow(String label, String value,
      {bool isLast = false, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: small ? 10 : 12,
                    color: small ? const Color(0xFF329AD6) : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5F5),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
        ),
        child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
      ),
      const SizedBox(height: 10),
      Text(message.metaRoomError ?? 'Failed to generate QR.',
          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5),
          textAlign: TextAlign.center),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => onRetryMetaRoom?.call(index),
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: cs.primary)),
        ),
        child: const Text('Try Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class _BotAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 32, height: 32,
      // decoration: BoxDecoration(
      //   shape: BoxShape.circle,
      //   color: cs.primary.withValues(alpha: 0.12),
      //   border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1.5),
      // ),
      child:Transform.flip(
        flipX: true,
        child:Image.asset('assets/images/user_icon.png', fit: BoxFit.cover),
      ),
    );
  }
}

// Animated shimmer skeleton QR — matches Angular mr-qr-skeleton SVG
class _SkeletonQr extends StatefulWidget {
  const _SkeletonQr();
  @override
  State<_SkeletonQr> createState() => _SkeletonQrState();
}

class _SkeletonQrState extends State<_SkeletonQr>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _anim = Tween(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: const Size(200, 200),
        painter: _SkeletonQrPainter(_anim.value),
      ),
    );
  }
}

class _SkeletonQrPainter extends CustomPainter {
  final double shimmerPos;
  _SkeletonQrPainter(this.shimmerPos);

  static const _dark = Color(0xFF9CA3AF);
  static const _light = Color(0xFFD1D5DB);
  static const _bg = Color(0xFFF3F4F6);

  // Each rect: [x, y, w, h, isDark]
  static const _rects = [
    // Top-left finder
    [10.0, 10.0, 56.0, 56.0, false],
    [18.0, 18.0, 40.0, 40.0, 2.0], // bg fill
    [26.0, 26.0, 24.0, 24.0, true],
    // Top-right finder
    [134.0, 10.0, 56.0, 56.0, false],
    [142.0, 18.0, 40.0, 40.0, 2.0],
    [150.0, 26.0, 24.0, 24.0, true],
    // Bottom-left finder
    [10.0, 134.0, 56.0, 56.0, false],
    [18.0, 142.0, 40.0, 40.0, 2.0],
    [26.0, 150.0, 24.0, 24.0, true],
    // Data pixels
    [78.0, 10.0, 8.0, 8.0, false], [90.0, 10.0, 8.0, 8.0, true],
    [102.0, 10.0, 8.0, 8.0, false], [114.0, 10.0, 8.0, 8.0, true],
    [78.0, 22.0, 8.0, 8.0, true], [102.0, 22.0, 8.0, 8.0, false],
    [114.0, 22.0, 8.0, 8.0, true], [78.0, 34.0, 8.0, 8.0, false],
    [90.0, 34.0, 8.0, 8.0, true], [114.0, 34.0, 8.0, 8.0, false],
    [78.0, 46.0, 8.0, 8.0, true], [90.0, 46.0, 8.0, 8.0, false],
    [102.0, 46.0, 8.0, 8.0, true], [78.0, 58.0, 8.0, 8.0, false],
    [114.0, 58.0, 8.0, 8.0, true],
    [10.0, 78.0, 8.0, 8.0, true], [22.0, 78.0, 8.0, 8.0, false],
    [46.0, 78.0, 8.0, 8.0, true], [58.0, 78.0, 8.0, 8.0, false],
    [10.0, 90.0, 8.0, 8.0, false], [34.0, 90.0, 8.0, 8.0, true],
    [58.0, 90.0, 8.0, 8.0, true], [10.0, 102.0, 8.0, 8.0, true],
    [22.0, 102.0, 8.0, 8.0, false], [46.0, 102.0, 8.0, 8.0, false],
    [10.0, 114.0, 8.0, 8.0, false], [34.0, 114.0, 8.0, 8.0, true],
    [58.0, 114.0, 8.0, 8.0, false],
    [78.0, 78.0, 8.0, 8.0, true], [90.0, 78.0, 8.0, 8.0, false],
    [102.0, 78.0, 8.0, 8.0, true], [114.0, 78.0, 8.0, 8.0, false],
    [78.0, 90.0, 8.0, 8.0, false], [102.0, 90.0, 8.0, 8.0, false],
    [114.0, 90.0, 8.0, 8.0, true], [78.0, 102.0, 8.0, 8.0, true],
    [90.0, 102.0, 8.0, 8.0, true], [114.0, 102.0, 8.0, 8.0, false],
    [78.0, 114.0, 8.0, 8.0, false], [102.0, 114.0, 8.0, 8.0, true],
    [114.0, 114.0, 8.0, 8.0, true],
    [134.0, 78.0, 8.0, 8.0, false], [146.0, 78.0, 8.0, 8.0, true],
    [170.0, 78.0, 8.0, 8.0, false], [182.0, 78.0, 8.0, 8.0, true],
    [134.0, 90.0, 8.0, 8.0, true], [158.0, 90.0, 8.0, 8.0, false],
    [182.0, 90.0, 8.0, 8.0, false], [146.0, 102.0, 8.0, 8.0, true],
    [170.0, 102.0, 8.0, 8.0, true], [134.0, 114.0, 8.0, 8.0, false],
    [158.0, 114.0, 8.0, 8.0, false], [182.0, 114.0, 8.0, 8.0, true],
    [78.0, 134.0, 8.0, 8.0, true], [90.0, 134.0, 8.0, 8.0, false],
    [114.0, 134.0, 8.0, 8.0, true], [134.0, 134.0, 8.0, 8.0, false],
    [158.0, 134.0, 8.0, 8.0, true], [182.0, 134.0, 8.0, 8.0, false],
    [78.0, 146.0, 8.0, 8.0, false], [102.0, 146.0, 8.0, 8.0, true],
    [146.0, 146.0, 8.0, 8.0, false], [170.0, 146.0, 8.0, 8.0, true],
    [78.0, 158.0, 8.0, 8.0, true], [90.0, 158.0, 8.0, 8.0, false],
    [114.0, 158.0, 8.0, 8.0, true], [134.0, 158.0, 8.0, 8.0, true],
    [158.0, 158.0, 8.0, 8.0, false], [78.0, 170.0, 8.0, 8.0, false],
    [102.0, 170.0, 8.0, 8.0, false], [114.0, 170.0, 8.0, 8.0, true],
    [146.0, 170.0, 8.0, 8.0, true], [182.0, 170.0, 8.0, 8.0, false],
    [78.0, 182.0, 8.0, 8.0, true], [90.0, 182.0, 8.0, 8.0, false],
    [114.0, 182.0, 8.0, 8.0, false], [134.0, 182.0, 8.0, 8.0, false],
    [170.0, 182.0, 8.0, 8.0, true],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Draw pixels
    for (final r in _rects) {
      final x = r[0] as double;
      final y = r[1] as double;
      final w = r[2] as double;
      final h = r[3] as double;
      final type = r[4];
      Color color;
      if (type == 2.0) {
        color = _bg;
      } else if (type == true) {
        color = _dark;
      } else {
        color = _light;
      }
      final rr = (w < 20) ? 1.0 : 6.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rr)),
        Paint()..color = color,
      );
    }
    // Shimmer sweep
    final shimmerRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(0),
      ).createShader(Rect.fromLTWH(
          shimmerPos * size.width, 0, size.width, size.height));
    canvas.drawRect(shimmerRect, shimmerPaint);
  }

  @override
  bool shouldRepaint(_SkeletonQrPainter old) => old.shimmerPos != shimmerPos;
}


class _FullScreenImageViewer extends StatelessWidget {
  final Uint8List bytes;
  const _FullScreenImageViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 8.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: Center(
                child: Image.memory(bytes,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity),
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CachedBase64Image extends StatefulWidget {
  final String base64;
  const _CachedBase64Image({required this.base64});
  @override
  State<_CachedBase64Image> createState() => _CachedBase64ImageState();
}

class _CachedBase64ImageState extends State<_CachedBase64Image> {
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64);
  }

  @override
  void didUpdateWidget(_CachedBase64Image old) {
    super.didUpdateWidget(old);
    if (old.base64 != widget.base64) _bytes = _decode(widget.base64);
  }

  static Uint8List _decode(String src) {
    try {
      final raw = src.contains(',') ? src.split(',').last : src;
      return base64Decode(raw);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes.isEmpty) {
      return const SizedBox(
        width: 120, height: 80,
        child: Center(child: Icon(Icons.broken_image, color: Color(0xFF94A3B8), size: 32)),
      );
    }
    return Image.memory(
      _bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image, color: Color(0xFF94A3B8), size: 48),
    );
  }
}
