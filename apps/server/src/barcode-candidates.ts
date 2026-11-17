/**
 * The barcodes to try for a scanned or typed code, in order. The app's
 * `barcodeCandidates` (apps/mobile/lib/domain/nutrition/open_food_facts.dart)
 * is the same rule; both run
 * packages/golden-vectors/vectors/m36-barcode-candidates.json, so an agent and
 * the app find the same product for the same code.
 *
 * Whitespace and hyphens are removed; anything that is not then 6 to 18 digits
 * is not a barcode. A 12-digit UPC-A code is also tried with a leading `0`, as
 * Open Food Facts usually stores it, and a 13-digit code starting with `0` is
 * also tried without it.
 */
export function barcodeCandidates(raw: string): string[] {
  const code = raw.replace(/[\s-]/g, "");
  if (!/^\d{6,18}$/.test(code)) {
    return [];
  }
  const candidates = [code];
  if (code.length === 12) {
    candidates.push(`0${code}`);
  }
  if (code.length === 13 && code.startsWith("0")) {
    candidates.push(code.slice(1));
  }
  return candidates;
}
