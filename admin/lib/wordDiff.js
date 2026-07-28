/**
 * Word-level diff (LCS). Texts here are single sentences, so the O(n·m) table is
 * irrelevant in cost and gives a much more readable result than a char diff.
 * Returns [{ type: 'same' | 'del' | 'ins', text }] with runs already merged.
 */
function tokenize(s) {
  return (s ?? '').split(/(\s+)/).filter((t) => t !== '');
}

function push(out, type, text) {
  const last = out[out.length - 1];
  if (last && last.type === type) last.text += text;
  else out.push({ type, text });
}

export function wordDiff(before, after) {
  const A = tokenize(before);
  const B = tokenize(after);
  const n = A.length;
  const m = B.length;

  // dp[i][j] = length of the LCS of A[i:] and B[j:]
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] = A[i] === B[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  const out = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (A[i] === B[j]) { push(out, 'same', A[i]); i++; j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) { push(out, 'del', A[i]); i++; }
    else { push(out, 'ins', B[j]); j++; }
  }
  while (i < n) push(out, 'del', A[i++]);
  while (j < m) push(out, 'ins', B[j++]);
  return out;
}

export function isChanged(before, after) {
  return String(before ?? '').trim() !== String(after ?? '').trim();
}
