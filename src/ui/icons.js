/*
 * Stage 2 SVG UI contract.
 *
 * The actual <symbol> artwork lives in index.html so static HUD/menu markup
 * can render before the game module is fully loaded.  This module is the
 * single typed-by-convention registry used by dynamic UI code and tests.
 * Every symbol uses viewBox="0 0 24 24"; line icons use stroke="currentColor"
 * and a consistent stroke width.  Car silhouettes are intentionally filled.
 */
export const ICON_NAMES = Object.freeze([
  'timer',
  'trophy',
  'medal',
  'flame',
  'target',
  'camera',
  'crosshair',
  'search',
  'eye',
  'rotate-ccw',
  'rotate-cw',
  'volume-2',
  'volume-x',
  'pause',
  'play',
  'flag',
  'route',
  'map',
  'map-pin',
  'gauge',
  'zap',
  'mountain',
  'navigation',
  'chevron-left',
  'chevron-right',
  'chevrons-up',
  'chevrons-down',
  'wind',
  'phone-rotate',
  'car',
  'gamepad',
  'steering-wheel',
  'sparkles',
  'smartphone',
  'home',
  'check',
  'move-horizontal',
  'palette',
  'alert-triangle',
  'traffic-light',
  'fuel',
  'wrench',
  'settings',
  'disc-brake',
  'car-coupe',
  'car-muscle',
  'car-sport',
  'car-hyper',
  'car-pickup',
]);

const ICON_NAME_SET = new Set(ICON_NAMES);

export function hasIcon(name) {
  return ICON_NAME_SET.has(name);
}

export function iconMarkup(name, className = 'ui-icon') {
  if (!hasIcon(name)) return '';
  const safeClassName = String(className || 'ui-icon')
    .replace(/[^a-zA-Z0-9 _-]/g, '')
    .trim() || 'ui-icon';
  return `<svg class="${safeClassName}" aria-hidden="true" focusable="false"><use href="#i-${name}"></use></svg>`;
}

export function setIcon(element, name, className = 'ui-icon') {
  if (!element) return false;
  const markup = iconMarkup(name, className);
  if (!markup) return false;
  element.innerHTML = markup;
  return true;
}
