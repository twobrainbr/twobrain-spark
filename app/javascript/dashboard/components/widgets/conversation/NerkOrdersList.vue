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
const context = ref(null);
const loading = ref(false);
const error = ref('');
const orders = computed(() => context.value?.commerce?.orders || []);
const loyalty = computed(() => context.value?.commerce?.loyalty);

const formatCurrency = (amount, currency = 'BRL') =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency,
  }).format((amount || 0) / 100);

const refundedAmount = order =>
  (order.payments || []).reduce(
    (total, payment) =>
      total +
      (payment.refunds || []).reduce(
        (refundTotal, refund) => refundTotal + (refund.amount_cents || 0),
        0
      ),
    0
  );

const fetchContext = async () => {
  if (!hasSearchableInfo.value) return;
  loading.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.getContext(props.contactId);
    context.value = response.data.context;
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, fetchContext, { immediate: true });
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12">
    <div v-if="loading" class="flex justify-center p-4">
      <Spinner size="32" class="text-n-brand" />
    </div>
    <p v-else-if="error" class="text-center text-n-ruby-11">
      {{ error }}
    </p>
    <p v-else-if="!hasSearchableInfo" class="text-center text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.NERK.MISSING_IDENTITY') }}
    </p>
    <div v-else class="flex flex-col gap-3">
      <div
        v-if="context?.customer || loyalty"
        class="flex items-center justify-between gap-3 rounded-lg bg-n-alpha-2 p-3"
      >
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ context?.customer?.name }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.NERK.IDENTITY_MATCHED') }}
          </p>
        </div>
        <div v-if="loyalty" class="text-right">
          <p class="text-sm font-medium text-n-slate-12">
            {{ loyalty.points_balance || 0 }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS') }}
          </p>
        </div>
      </div>

      <p v-if="!orders.length" class="text-center text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.NERK.NO_ORDERS') }}
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
                  number: order.order_number,
                })
              }}
            </strong>
            <span
              class="rounded bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >
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
            <span>
              {{
                formatCurrency(
                  order.amounts.total_cents,
                  order.amounts.currency
                )
              }}
            </span>
          </div>
          <div class="flex flex-wrap gap-2 text-xs">
            <span class="rounded bg-n-alpha-2 px-2 py-1 text-n-slate-11">
              {{
                t('CONVERSATION_SIDEBAR.NERK.PAYMENT_STATUS', {
                  status: order.payment_status,
                })
              }}
            </span>
            <span
              v-if="refundedAmount(order)"
              class="rounded bg-n-ruby-3 px-2 py-1 text-n-ruby-11"
            >
              {{
                t('CONVERSATION_SIDEBAR.NERK.REFUNDED', {
                  amount: formatCurrency(
                    refundedAmount(order),
                    order.amounts.currency
                  ),
                })
              }}
            </span>
          </div>
          <div
            v-if="order.shipping.shipments.length"
            class="flex flex-col gap-1 text-xs text-n-slate-11"
          >
            <span
              v-for="shipment in order.shipping.shipments"
              :key="shipment.tracking_code || shipment.provider"
            >
              {{
                t('CONVERSATION_SIDEBAR.NERK.SHIPMENT', {
                  service: shipment.service || shipment.provider,
                  tracking: shipment.tracking_code || shipment.status,
                })
              }}
            </span>
          </div>
        </article>
      </div>
    </div>
  </div>
</template>
