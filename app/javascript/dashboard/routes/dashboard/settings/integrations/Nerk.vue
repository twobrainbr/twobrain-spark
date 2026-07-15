<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import integrationAPI from 'dashboard/api/integrations';

import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Integration from './Integration.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const integration = useFunctionGetter('integrations/getIntegration', 'nerk');
const uiFlags = useMapGetter('integrations/getUIFlags');

const integrationLoaded = ref(false);
const baseUrl = ref('');
const apiToken = ref('');
const error = ref('');
const isSubmitting = ref(false);

const integrationAction = computed(() =>
  integration.value.enabled ? 'disconnect' : 'connect'
);

const connect = async () => {
  error.value = '';
  isSubmitting.value = true;
  try {
    await integrationAPI.connectNerk({
      baseUrl: baseUrl.value.trim(),
      apiToken: apiToken.value.trim(),
    });
    apiToken.value = '';
    await store.dispatch('integrations/get');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('INTEGRATION_SETTINGS.NERK.ERROR');
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(async () => {
  await store.dispatch('integrations/get');
  integrationLoaded.value = true;
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded || uiFlags.isFetching">
    <template #header>
      <BaseSettingsHeader
        :title="t('INTEGRATION_SETTINGS.NERK.HEADER')"
        description=""
        feature-name="nerk"
        :back-button-label="t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <Integration
          :integration-id="integration.id"
          :integration-logo="integration.logo"
          :integration-name="integration.name"
          :integration-description="integration.description"
          :integration-enabled="integration.enabled"
          :integration-action="integrationAction"
          :delete-confirmation-text="{
            title: t('INTEGRATION_SETTINGS.NERK.DELETE.TITLE'),
            message: t('INTEGRATION_SETTINGS.NERK.DELETE.MESSAGE'),
          }"
        >
          <template #action>
            <span class="text-sm text-n-slate-11">
              {{ t('INTEGRATION_SETTINGS.NERK.CONFIGURE_BELOW') }}
            </span>
          </template>
        </Integration>

        <form
          v-if="!integration.enabled"
          class="flex max-w-2xl flex-col gap-4 rounded-xl bg-n-card p-6 outline outline-1 outline-n-container"
          @submit.prevent="connect"
        >
          <Input
            v-model="baseUrl"
            type="url"
            required
            :label="t('INTEGRATION_SETTINGS.NERK.BASE_URL.LABEL')"
            :placeholder="t('INTEGRATION_SETTINGS.NERK.BASE_URL.PLACEHOLDER')"
          />
          <Input
            v-model="apiToken"
            type="password"
            required
            :label="t('INTEGRATION_SETTINGS.NERK.API_TOKEN.LABEL')"
            :placeholder="t('INTEGRATION_SETTINGS.NERK.API_TOKEN.PLACEHOLDER')"
          />
          <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
          <div>
            <Button
              type="submit"
              blue
              :is-loading="isSubmitting"
              :label="t('INTEGRATION_SETTINGS.NERK.CONNECT')"
            />
          </div>
        </form>
      </div>
    </template>
  </SettingsLayout>
</template>
