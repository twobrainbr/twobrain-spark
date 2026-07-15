<script>
import SnackbarContainer from './components/SnackBar/Container.vue';
import {
  ACCOUNT_APPEARANCE_PREVIEW_EVENT,
  ACCOUNT_FONT_CLASSES,
  DEFAULT_ACCOUNT_APPEARANCE,
  applyAccountAppearance,
} from 'dashboard/helper/accountTheme';

export default {
  components: { SnackbarContainer },
  data() {
    return { theme: 'light', appearancePreview: null };
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
        this.appearancePreview?.font_family ||
        this.currentAccount?.custom_attributes?.font_family ||
        DEFAULT_ACCOUNT_APPEARANCE.font_family;
      return ACCOUNT_FONT_CLASSES[fontFamily] || ACCOUNT_FONT_CLASSES.system;
    },
  },
  watch: {
    currentAccount: {
      deep: true,
      handler() {
        this.applyAccountAppearance();
      },
    },
    appearancePreview: {
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
    window.addEventListener(
      ACCOUNT_APPEARANCE_PREVIEW_EVENT,
      this.updateAppearancePreview
    );
    this.applyAccountAppearance();
  },
  beforeUnmount() {
    window.removeEventListener(
      ACCOUNT_APPEARANCE_PREVIEW_EVENT,
      this.updateAppearancePreview
    );
  },
  methods: {
    updateAppearancePreview(event) {
      this.appearancePreview = event.detail;
    },
    applyAccountAppearance() {
      const attributes = this.currentAccount?.custom_attributes || {};
      applyAccountAppearance({ ...attributes, ...this.appearancePreview });
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
