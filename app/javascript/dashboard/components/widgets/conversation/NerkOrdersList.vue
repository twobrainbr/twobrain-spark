<script setup>
import { computed, ref, watch } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import NerkAPI from 'dashboard/api/integrations/nerk';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});
const { t } = useI18n();

const contact = useFunctionGetter('contacts/getContact', props.contactId);
const hasSearchableInfo = computed(
  () => !!contact.value?.email || !!contact.value?.phone_number
);
const orders = ref([]);
const loading = ref(false);
const error = ref('');

const formatCurrency = (amount, currency = 'BRL') =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency,
  }).format((amount || 0) / 100);

const fetchOrders = async () => {
  if (!hasSearchableInfo.value) return;
  loading.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.getOrders(props.contactId);
    orders.value = response.data.orders;
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, fetchOrders, { immediate: true });
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12">
    <div v-if="loading" class="flex justify-center p-4">
      <Spinner size="32" class="text-n-brand" />
    </div>
    <p v-else-if="error" class="text-center text-n-ruby-11">
      {{ error }}
    </p>
    <p
      v-else-if="!hasSearchableInfo || !orders.length"
      class="text-center text-n-slate-11"
    >
      {{ $t('CONVERSATION_SIDEBAR.NERK.NO_ORDERS') }}
    </p>
    <div v-else class="flex flex-col divide-y divide-n-weak">
      <article
        v-for="order in orders"
        :key="order.id"
        class="flex flex-col gap-2 py-3"
      >
        <div class="flex items-center justify-between gap-2">
          <strong class="truncate text-sm">
            {{
              t('CONVERSATION_SIDEBAR.NERK.ORDER_NUMBER', {
                number: order.orderNumber,
              })
            }}
          </strong>
          <span class="rounded bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11">
            {{ order.status }}
          </span>
        </div>
        <div class="flex justify-between text-sm text-n-slate-11">
          <span>
            {{
              t('CONVERSATION_SIDEBAR.NERK.ITEMS', {
                count: order.items.length,
              })
            }}
          </span>
          <span>{{ formatCurrency(order.totalCents, order.currency) }}</span>
        </div>
        <div
          v-if="order.shipments.length"
          class="flex flex-col gap-1 text-xs text-n-slate-11"
        >
          <span v-for="shipment in order.shipments" :key="shipment.id">
            {{
              t('CONVERSATION_SIDEBAR.NERK.SHIPMENT', {
                service: shipment.service || shipment.provider,
                tracking: shipment.trackingCode || shipment.status,
              })
            }}
          </span>
        </div>
      </article>
    </div>
  </div>
</template>
