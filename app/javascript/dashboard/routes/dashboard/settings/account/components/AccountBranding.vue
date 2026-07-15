<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';
import SectionLayout from './SectionLayout.vue';

const DEFAULT_APPEARANCE = {
  brand_color: '#5E8902',
  accent_color: '#507605',
  background_color: '#F7F7F7',
  surface_color: '#FEFEFE',
  sidebar_color: '#F7F7F7',
  text_color: '#1C2024',
  font_family: 'system',
};
const HEX_COLOR_PATTERN = /^#[\dA-F]{6}$/i;

const COLOR_FIELDS = [
  'brand_color',
  'accent_color',
  'background_color',
  'surface_color',
  'sidebar_color',
  'text_color',
];

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const appearance = reactive({ ...DEFAULT_APPEARANCE });
const logoFile = ref(null);
const logoUrl = ref('');
const removeLogo = ref(false);
const isSaving = ref(false);

const colorFields = computed(() => [
  {
    name: 'brand_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.brand_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.brand_color.HELP'),
  },
  {
    name: 'accent_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.accent_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.accent_color.HELP'),
  },
  {
    name: 'background_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.background_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.background_color.HELP'),
  },
  {
    name: 'surface_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.surface_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.surface_color.HELP'),
  },
  {
    name: 'sidebar_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.sidebar_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.sidebar_color.HELP'),
  },
  {
    name: 'text_color',
    label: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.text_color.LABEL'),
    help: t('GENERAL_SETTINGS.FORM.BRANDING.FIELDS.text_color.HELP'),
  },
]);

const fontOptions = computed(() => [
  { value: 'system', label: t('GENERAL_SETTINGS.FORM.BRANDING.FONTS.system') },
  { value: 'hanken', label: t('GENERAL_SETTINGS.FORM.BRANDING.FONTS.hanken') },
  { value: 'inter', label: t('GENERAL_SETTINGS.FORM.BRANDING.FONTS.inter') },
  { value: 'serif', label: t('GENERAL_SETTINGS.FORM.BRANDING.FONTS.serif') },
]);

const enrichedLogo = account => {
  const logos = account?.custom_attributes?.brand_info?.logos || [];
  const squareLogo = logos.find(logo => logo.resolution?.aspect_ratio === 1);
  return (squareLogo || logos[0])?.url || '';
};

const enrichedColor = account =>
  account?.custom_attributes?.brand_info?.colors?.[0]?.hex;

const initializeBranding = account => {
  if (!account) return;

  Object.assign(appearance, DEFAULT_APPEARANCE, account.custom_attributes);
  appearance.brand_color =
    account.custom_attributes?.brand_color ||
    enrichedColor(account) ||
    DEFAULT_APPEARANCE.brand_color;
  appearance.accent_color =
    account.custom_attributes?.accent_color || appearance.brand_color;
  logoUrl.value = account.logo_url || enrichedLogo(account);
  logoFile.value = null;
  removeLogo.value = false;
};

watch(currentAccount, initializeBranding, { immediate: true });

const areColorsValid = computed(() =>
  COLOR_FIELDS.every(field => HEX_COLOR_PATTERN.test(appearance[field]))
);

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

const updateColorFromPicker = (field, event) => {
  appearance[field] = event.target.value.toUpperCase();
};

const resetAppearance = () => Object.assign(appearance, DEFAULT_APPEARANCE);

const saveBranding = async () => {
  if (!areColorsValid.value) {
    useAlert(t('GENERAL_SETTINGS.FORM.BRANDING.COLOR_ERROR'));
    return;
  }

  const formData = new FormData();
  COLOR_FIELDS.forEach(field => {
    formData.append(field, appearance[field].toUpperCase());
  });
  formData.append('font_family', appearance.font_family);
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

      <div class="grid gap-5 sm:grid-cols-2">
        <div
          v-for="field in colorFields"
          :key="field.name"
          class="flex flex-col gap-2"
        >
          <label
            class="text-sm font-medium text-n-slate-12"
            :for="`appearance-${field.name}`"
          >
            {{ field.label }}
          </label>
          <div class="flex items-center gap-3">
            <input
              :id="`appearance-${field.name}-picker`"
              :value="
                HEX_COLOR_PATTERN.test(appearance[field.name])
                  ? appearance[field.name]
                  : DEFAULT_APPEARANCE[field.name]
              "
              type="color"
              class="size-10 cursor-pointer rounded-lg border border-n-weak bg-n-background p-1"
              @input="updateColorFromPicker(field.name, $event)"
            />
            <NextInput
              :id="`appearance-${field.name}`"
              v-model="appearance[field.name]"
              class="max-w-40"
              type="text"
              :placeholder="DEFAULT_APPEARANCE[field.name]"
            />
          </div>
          <span class="text-xs text-n-slate-10">
            {{ field.help }}
          </span>
        </div>
      </div>

      <div class="flex flex-col gap-2 sm:max-w-sm">
        <label class="text-sm font-medium text-n-slate-12" for="font-family">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.FONT_FAMILY') }}
        </label>
        <select
          id="font-family"
          v-model="appearance.font_family"
          class="h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm text-n-slate-12"
        >
          <option
            v-for="font in fontOptions"
            :key="font.value"
            :value="font.value"
          >
            {{ font.label }}
          </option>
        </select>
        <span class="text-xs text-n-slate-10">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.FONT_HELP') }}
        </span>
      </div>

      <div class="flex gap-3">
        <NextButton blue type="submit" :is-loading="isSaving">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.SUBMIT') }}
        </NextButton>
        <NextButton slate type="button" @click="resetAppearance">
          {{ t('GENERAL_SETTINGS.FORM.BRANDING.RESET') }}
        </NextButton>
      </div>
    </form>
  </SectionLayout>
</template>
