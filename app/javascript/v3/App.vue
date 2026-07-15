<script>
import SnackbarContainer from './components/SnackBar/Container.vue';

const DEFAULT_APPEARANCE = {
  brand_color: '#5E8902',
  accent_color: '#507605',
  background_color: '#F7F7F7',
  surface_color: '#FEFEFE',
  sidebar_color: '#F7F7F7',
  text_color: '#1C2024',
  font_family: 'system',
};

const FONT_CLASSES = {
  system: 'font-system',
  hanken: 'font-sans',
  inter: 'font-inter',
  serif: 'font-serif',
};

export default {
  components: { SnackbarContainer },
  data() {
    return { theme: 'light' };
  },
  computed: {
    currentAccount() {
      const accountId = Number(this.$route?.params?.accountId);
      return accountId
        ? this.$store.getters['accounts/getAccount'](accountId)
        : null;
    },
    fontClass() {
      const fontFamily =
        this.currentAccount?.custom_attributes?.font_family ||
        DEFAULT_APPEARANCE.font_family;
      return FONT_CLASSES[fontFamily] || FONT_CLASSES.system;
    },
  },
  watch: {
    currentAccount: {
      deep: true,
      handler() {
        this.applyAccountAppearance();
      },
    },
  },
  mounted() {
    this.setColorTheme();
    this.listenToThemeChanges();
    this.setLocale(window.chatwootConfig.selectedLocale);
    this.applyAccountAppearance();
  },
  methods: {
    colorToRgb(color, fallback) {
      const match = (color || fallback).match(
        /^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i
      );
      return (
        match || fallback.match(/^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i)
      )
        .slice(1)
        .map(channel => Number.parseInt(channel, 16))
        .join(' ');
    },
    applyAccountAppearance() {
      const attributes = this.currentAccount?.custom_attributes || {};
      const enrichedColor = attributes.brand_info?.colors?.[0]?.hex;
      const appearance = {
        ...DEFAULT_APPEARANCE,
        ...attributes,
        brand_color:
          attributes.brand_color ||
          enrichedColor ||
          DEFAULT_APPEARANCE.brand_color,
        accent_color:
          attributes.accent_color ||
          attributes.brand_color ||
          enrichedColor ||
          DEFAULT_APPEARANCE.accent_color,
      };
      const variables = {
        '--brand-color': 'brand_color',
        '--blue-10': 'accent_color',
        '--blue-11': 'accent_color',
        '--background-color': 'background_color',
        '--surface-1': 'surface_color',
        '--surface-2': 'surface_color',
        '--solid-1': 'surface_color',
        '--account-sidebar-color': 'sidebar_color',
        '--slate-12': 'text_color',
      };

      Object.entries(variables).forEach(([variable, field]) => {
        const rgb = this.colorToRgb(
          appearance[field],
          DEFAULT_APPEARANCE[field]
        );
        document.documentElement.style.setProperty(variable, rgb);
      });
    },
    setColorTheme() {
      if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
        this.theme = 'dark';
        document.documentElement.classList.add('dark');
      } else {
        this.theme = 'light';
        document.documentElement.classList.remove('dark');
      }
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');

      mql.onchange = e => {
        if (e.matches) {
          this.theme = 'dark';
          document.documentElement.classList.add('dark');
        } else {
          this.theme = 'light';
          document.documentElement.classList.remove('dark');
        }
      };
    },
    setLocale(locale) {
      if (locale) {
        this.$root.$i18n.locale = locale;
      }
    },
  },
};
</script>

<template>
  <div
    class="h-full min-h-screen w-full antialiased"
    :class="[theme, fontClass]"
  >
    <router-view />
    <SnackbarContainer />
  </div>
</template>

<style lang="scss">
@tailwind base;
@tailwind components;
@tailwind utilities;

@import '../dashboard/assets/scss/next-colors';

html,
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
    Oxygen-Sans, Ubuntu, Cantarell, 'Helvetica Neue', sans-serif;
  @apply h-full w-full;

  input,
  select {
    outline: none;
  }
}

.text-link {
  @apply text-n-brand font-medium hover:text-n-blue-10;
}

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
