/// One line of a diff: ' ' unchanged, '-' removed, '+' added.
class DiffLine {
  const DiffLine(this.op, this.text);
  final String op;
  final String text;
}

/// Line diff by longest common subsequence. Inputs are capped so a pasted wall of text cannot stall the UI.
List<DiffLine> diffLines(String before, String after, {int maxLines = 400}) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  if (a.length > maxLines || b.length > maxLines) {
    return [
      for (final l in a) DiffLine('-', l),
      for (final l in b) DiffLine('+', l),
    ];
  }
  final dp = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add(DiffLine(' ', a[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(DiffLine('-', a[i++]));
    } else {
      out.add(DiffLine('+', b[j++]));
    }
  }
  while (i < a.length) {
    out.add(DiffLine('-', a[i++]));
  }
  while (j < b.length) {
    out.add(DiffLine('+', b[j++]));
  }
  return out;
}

/// Counts of changed lines, for a one-line summary.
({int added, int removed}) diffStats(List<DiffLine> d) => (added: d.where((l) => l.op == '+').length, removed: d.where((l) => l.op == '-').length);
