<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFunctionGetter, useStore } from 'dashboard/composables/store';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const store = useStore();
const { t } = useI18n();
const integration = useFunctionGetter('integrations/getIntegration', 'nerk');
const integrationLoaded = ref(false);

onMounted(async () => {
  await store.dispatch('integrations/get', 'nerk');
  integrationLoaded.value = true;
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded">
    <template #header>
      <BaseSettingsHeader
        :title="t('INTEGRATION_SETTINGS.NERK.HEADER')"
        :description="t('INTEGRATION_SETTINGS.NERK.DESCRIPTION')"
        feature-name="nerk_integration"
        :back-button-label="t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div
        class="flex max-w-2xl items-start gap-4 rounded-xl bg-n-card p-6 outline outline-1 outline-n-container"
      >
        <img
          :src="`/dashboard/images/integrations/${integration.logo}`"
          :alt="integration.name"
          class="h-14 w-14 rounded-md border border-n-weak bg-n-alpha-3"
        />
        <div class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
            <h3 class="text-heading-1 text-n-slate-12">
              {{ integration.name }}
            </h3>
            <span
              class="rounded-full bg-n-teal-3 px-2 py-1 text-xs font-medium text-n-teal-11"
            >
              {{ t('INTEGRATION_SETTINGS.NERK.CONNECTED') }}
            </span>
          </div>
          <p class="text-body-main text-n-slate-11">
            {{ t('INTEGRATION_SETTINGS.NERK.SUPER_ADMIN_MANAGED') }}
          </p>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
