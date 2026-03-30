import 'dart:html' as html;

/// Opens a URL using the anchor-element trick (bypasses iOS Chrome popup blocker).
void openUrl(Uri uri) {
  final anchor = html.AnchorElement()
    ..href = uri.toString()
    ..target = '_blank'
    ..rel = 'noopener noreferrer';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
