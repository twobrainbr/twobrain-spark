export const ACCOUNT_APPEARANCE_PREVIEW_EVENT = 'account-appearance-preview';

export const DEFAULT_ACCOUNT_APPEARANCE = {
  brand_color: '#5E8902',
  accent_color: '#507605',
  background_color: '#F7F7F7',
  surface_color: '#FEFEFE',
  sidebar_color: '#F7F7F7',
  text_color: '#1C2024',
  font_family: 'system',
};

export const ACCOUNT_FONT_CLASSES = {
  system: 'font-system',
  hanken: 'font-sans',
  inter: 'font-inter',
  serif: 'font-serif',
};

const HEX_COLOR_PATTERN = /^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i;

const hexToRgb = (color, fallback) => {
  const match = (color || fallback).match(HEX_COLOR_PATTERN);
  const fallbackMatch = fallback.match(HEX_COLOR_PATTERN);

  return (match || fallbackMatch)
    .slice(1)
    .map(channel => Number.parseInt(channel, 16));
};

const mix = (color, target, targetWeight) =>
  color.map((channel, index) =>
    Math.round(channel * (1 - targetWeight) + target[index] * targetWeight)
  );

const cssVariableValue = color =>
  color.length === 4 ? color.join(', ') : color.join(' ');

const colorScale = (brand, accent) => ({
  1: mix(brand, [255, 255, 255], 0.97),
  2: mix(brand, [255, 255, 255], 0.94),
  3: mix(brand, [255, 255, 255], 0.88),
  4: mix(brand, [255, 255, 255], 0.8),
  5: mix(brand, [255, 255, 255], 0.68),
  6: mix(brand, [255, 255, 255], 0.55),
  7: mix(brand, [255, 255, 255], 0.4),
  8: mix(brand, [255, 255, 255], 0.2),
  9: brand,
  10: accent,
  11: mix(accent, [0, 0, 0], 0.25),
  12: mix(brand, [0, 0, 0], 0.65),
});

export const resolveAccountAppearance = attributes => {
  const enrichedColor = attributes?.brand_info?.colors?.[0]?.hex;
  const brandColor =
    attributes?.brand_color ||
    enrichedColor ||
    DEFAULT_ACCOUNT_APPEARANCE.brand_color;

  return {
    ...DEFAULT_ACCOUNT_APPEARANCE,
    ...attributes,
    brand_color: brandColor,
    accent_color: attributes?.accent_color || brandColor,
  };
};

export const applyAccountAppearance = attributes => {
  const appearance = resolveAccountAppearance(attributes);
  const brand = hexToRgb(
    appearance.brand_color,
    DEFAULT_ACCOUNT_APPEARANCE.brand_color
  );
  const accent = hexToRgb(
    appearance.accent_color,
    DEFAULT_ACCOUNT_APPEARANCE.accent_color
  );
  const background = hexToRgb(
    appearance.background_color,
    DEFAULT_ACCOUNT_APPEARANCE.background_color
  );
  const surface = hexToRgb(
    appearance.surface_color,
    DEFAULT_ACCOUNT_APPEARANCE.surface_color
  );
  const sidebar = hexToRgb(
    appearance.sidebar_color,
    DEFAULT_ACCOUNT_APPEARANCE.sidebar_color
  );
  const text = hexToRgb(
    appearance.text_color,
    DEFAULT_ACCOUNT_APPEARANCE.text_color
  );
  const scale = colorScale(brand, accent);
  const variables = {
    '--brand-color': brand,
    '--account-sidebar-color': sidebar,
    '--background-color': background,
    '--surface-1': surface,
    '--surface-2': surface,
    '--surface-active': mix(surface, text, 0.06),
    '--solid-1': surface,
    '--solid-2': mix(surface, text, 0.03),
    '--solid-3': mix(surface, text, 0.06),
    '--solid-active': mix(surface, text, 0.1),
    '--slate-12': text,
    '--gray-12': text,
    '--text-blue': scale[11],
    '--border-blue': [...scale[9], 0.5],
    '--border-blue-strong': scale[11],
    '--solid-blue': scale[3],
    '--solid-blue-2': scale[1],
    '--solid-iris': scale[3],
  };

  Object.entries(scale).forEach(([step, color]) => {
    variables[`--blue-${step}`] = color;
    variables[`--iris-${step}`] = color;
  });

  const wootScale = {
    25: scale[1],
    50: scale[2],
    75: scale[3],
    100: scale[4],
    200: scale[5],
    300: scale[7],
    400: scale[8],
    500: scale[9],
    600: scale[10],
    700: scale[11],
    800: mix(brand, [0, 0, 0], 0.45),
    900: scale[12],
  };

  Object.entries(wootScale).forEach(([step, color]) => {
    variables[`--woot-${step}`] = color;
  });

  Object.entries(variables).forEach(([variable, color]) => {
    document.documentElement.style.setProperty(
      variable,
      cssVariableValue(color)
    );
  });

  return appearance;
};
