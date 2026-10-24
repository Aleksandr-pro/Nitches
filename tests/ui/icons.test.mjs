import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { ICON_NAMES, hasIcon, iconMarkup } from '../../src/ui/icons.js';

const indexHtml = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
const mainJs = readFileSync(new URL('../../src/main.js', import.meta.url), 'utf8');
const css = readFileSync(new URL('../../src/style.css', import.meta.url), 'utf8');

function unique(values) {
  return [...new Set(values)];
}

test('SVG sprite exactly matches the dynamic icon registry', () => {
  const symbols = [...indexHtml.matchAll(/<symbol id="i-([a-z0-9-]+)" viewBox="0 0 24 24">/g)]
    .map((match) => match[1]);

  assert.equal(symbols.length, unique(symbols).length, 'sprite must not contain duplicate symbols');
  assert.deepEqual([...symbols].sort(), [...ICON_NAMES].sort());

  for (const name of ICON_NAMES) {
    const start = indexHtml.indexOf(`<symbol id="i-${name}"`);
    const end = indexHtml.indexOf('</symbol>', start);
    assert.ok(start >= 0 && end > start, `missing symbol ${name}`);
    assert.match(indexHtml.slice(start, end), /currentColor/, `${name} must inherit currentColor`);
  }
});

test('all static and generated icon references resolve to sprite symbols', () => {
  const staticRefs = [...indexHtml.matchAll(/href="#i-([a-z0-9-]+)"/g)].map((match) => match[1]);
  const dynamicRefs = [...mainJs.matchAll(/iconMarkup\('([a-z0-9-]+)'/g)].map((match) => match[1]);
  const silhouettes = [...mainJs.matchAll(/silhouette: '([a-z0-9-]+)'/g)].map((match) => match[1]);

  assert.ok(staticRefs.length >= 35, 'main HUD/menu markup should use the SVG sprite');
  assert.equal(silhouettes.length, 5, 'every player car needs a silhouette icon');
  for (const name of [...staticRefs, ...dynamicRefs, ...silhouettes]) {
    assert.ok(hasIcon(name), `unknown icon reference: ${name}`);
  }
});

test('icon markup is decorative, focus-safe, and rejects unknown icons', () => {
  const markup = iconMarkup('flag', 'ui-icon menu-icon');
  assert.match(markup, /<svg class="ui-icon menu-icon"/);
  assert.match(markup, /aria-hidden="true"/);
  assert.match(markup, /focusable="false"/);
  assert.match(markup, /href="#i-flag"/);
  assert.equal(iconMarkup('not-a-real-icon'), '');
});

test('interface sources no longer use emoji or car emoji fields', () => {
  const banned = [
    '⏱', '🏆', '🔥', '🎯', '🎥', '🔍', '🔊', '🔇', '⏸', '⚡', '🌿', '💨',
    '📱', '🏁', '🚗', '🎮', '🌅', '🏎', '🚦', '🔁', '🏠', '🗺', '🥇',
    '🥈', '🥉', '🎉', '💥', '🎨', '🎡', '✨', '🇯🇵', '🐎', '🦅', '🛻',
  ];

  for (const glyph of banned) {
    assert.ok(!indexHtml.includes(glyph), `index.html still contains ${glyph}`);
    assert.ok(!mainJs.includes(glyph), `src/main.js still contains ${glyph}`);
  }
  assert.ok(!mainJs.includes('car.emoji'));
  assert.ok(!/\n\s*emoji:/.test(mainJs));
});

test('icon-only HUD controls and touch controls have accessible labels', () => {
  for (const id of [
    'btnCamera',
    'btnCameraReset',
    'btnInspect',
    'btnRespawn',
    'btnSound',
    'btnPause',
    'btnLeft',
    'btnRight',
    'btnNitro',
    'btnДрифт',
    'btnBrake',
    'btnGas',
  ]) {
    const pattern = new RegExp(`id="${id}"[^>]*aria-label="[^"]+"`);
    assert.match(indexHtml, pattern, `${id} needs an aria-label`);
  }
});

test('CSS defines one icon sizing and interaction system', () => {
  assert.match(css, /\.ui-icon\s*\{/);
  assert.match(css, /\.icon-btn \.ui-icon\s*\{/);
  assert.match(css, /\.touch-btn \.ui-icon\s*\{/);
  assert.match(css, /\.car-silhouette\s*\{/);
  assert.match(css, /button:focus-visible/);
  assert.match(css, /@media \(max-width: 560px\)[\s\S]*\.icon-btn/);
});
