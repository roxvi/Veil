import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';

// The renderer is a compiled snapshot. Keep this small, idempotent extension
// readable and fail packaging if an upstream snapshot changes its anchors.
export async function patchBackground(clientRoot) {
  const rendererPath = join(clientRoot, 'assets/index-C7zerVBL.js');
  const stylesPath = join(clientRoot, 'assets/index-C4HyK4AY.css');
  let renderer = await readFile(rendererPath, 'utf8');
  let styles = await readFile(stylesPath, 'utf8');
  const anchor = '"--glass-opacity":s["glass-opacity"],';
  const variable = '"--glass-color":/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(s["glass-color"]||"")?s["glass-color"]:"#14171c",';
  if (!renderer.includes(variable)) {
    if (renderer.split(anchor).length !== 2) throw new Error('Cannot locate Veil background style binding');
    renderer = renderer.replace(anchor, anchor + variable);
  }

  // Tint only the existing window background. Xterm and each split remain
  // transparent; no overlays, filters or extra work enter the PTY write path.
  const original = 'rgba(20,23,28,var(--glass-opacity))';
  const tinted = 'color-mix(in srgb,var(--glass-color,#14171c) calc(var(--glass-opacity)*100%),transparent)';
  const count = styles.split(original).length - 1;
  if (count === 2) styles = styles.replaceAll(original, tinted);
  else if (count !== 0 || styles.split(tinted).length !== 3) throw new Error('Cannot locate Veil background rules');
  await writeFile(rendererPath, renderer);
  await writeFile(stylesPath, styles);
}

await patchBackground(process.env.VEIL_CLIENT_ROOT || resolve(import.meta.dirname, '../release/Veil Terminal.app/Contents/Resources/app/dist/client'));
console.log('Patched Veil background tint');
