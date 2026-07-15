<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';
import SectionLayout from './SectionLayout.vue';

const DEFAULT_BRAND_COLOR = '#5E8902';
const HEX_COLOR_PATTERN = /^#[\dA-F]{6}$/i;

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const brandColor = ref(DEFAULT_BRAND_COLOR);
const logoFile = ref(null);
const logoUrl = ref('');
const removeLogo = ref(false);
const isSaving = ref(false);

const enrichedLogo = account => {
  const logos = account?.custom_attributes?.brand_info?.logos || [];
  const squareLogo = logos.find(logo => logo.resolution?.aspect_ratio === 1);
  return (squareLogo || logos[0])?.url || '';
};

const enrichedColor = account =>
  account?.custom_attributes?.brand_info?.colors?.[0]?.hex;

const initializeBranding = account => {
  if (!account) return;

  brandColor.value =
    account.custom_attributes?.brand_color ||
    enrichedColor(account) ||
    DEFAULT_BRAND_COLOR;
  logoUrl.value = account.logo_url || enrichedLogo(account);
  logoFile.value = null;
  removeLogo.value = false;
};

watch(currentAccount, initializeBranding, { immediate: true });

const isColorValid = computed(() => HEX_COLOR_PATTERN.test(brandColor.value));

const updateLogo = ({ file, url }) => {
  logoFile.value = file;
  logoUrl.value = url;
  removeLogo.value = false;
};

const deleteLogo = () => {
  logoFile.value = null;
  logoUrl.value = '';
  removeLogo.value = true;
};

const updateColorFromPicker = event => {
  brandColor.value = event.target.value.toUpperCase();
};

const saveBranding = async () => {
  if (!isColorValid.value) {
    useAlert(t('GENERAL_SETTINGS.FORM.BRANDING.COLOR_ERROR'));
    return;
  }

  const formData = new FormData();
  formData.append('brand_color', brandColor.value.toUpperCase());
  if (logoFile.value) formData.append('logo', logoFile.value);
  if (removeLogo.value) formData.append('remove_logo', 'true');

  isSaving.value = true;
  try {
    await store.dispatch('accounts/update', { formData });
    useAlert(t('GENERAL_SETTINGS.FORM.BRANDING.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.BRANDING.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    with-border
    :title="t('GENERAL_SETTINGS.FORM.BRANDING.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.BRANDING.NOTE')"
  >
    <form class="grid gap-6" @submit.prevent="saveBranding">
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.LOGO') }}
        </span>
        <Avatar
          :src="logoUrl"
          :name="currentAccount?.name || ''"
          :size="72"
          allow-upload
          @upload="updateLogo"
          @delete="deleteLogo"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.LOGO_HELP') }}
        </span>
      </div>

      <div class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12" for="brand-color">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.COLOR') }}
        </label>
        <div class="flex items-center gap-3">
          <input
            id="brand-color-picker"
            :value="isColorValid ? brandColor : DEFAULT_BRAND_COLOR"
            type="color"
            class="size-10 cursor-pointer rounded-lg border border-n-weak bg-n-background p-1"
            @input="updateColorFromPicker"
          />
          <NextInput
            id="brand-color"
            v-model="brandColor"
            class="max-w-40"
            type="text"
            placeholder="#5E8902"
          />
        </div>
        <span class="text-xs text-n-slate-10">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.COLOR_HELP') }}
        </span>
      </div>

      <div>
        <NextButton blue type="submit" :is-loading="isSaving">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.SUBMIT') }}
        </NextButton>
      </div>
    </form>
  </SectionLayout>
</template>
