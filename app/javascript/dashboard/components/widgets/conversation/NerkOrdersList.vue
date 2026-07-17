<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import NerkAPI from 'dashboard/api/integrations/nerk';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import NerkAssistedSaleDialog from './NerkAssistedSaleDialog.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});
const { t } = useI18n();

const contact = useFunctionGetter('contacts/getContact', props.contactId);
const hasSearchableInfo = computed(() => !!contact.value?.id);
const context = ref(null);
const orderDialog = ref(null);
const assistedSaleDialog = ref(null);
const selectedOrder = ref(null);
const activeView = ref('profile');
const loading = ref(false);
const loadingCarts = ref(false);
const error = ref('');
const identityRequired = ref(false);
const leadName = ref(contact.value?.name || '');
const leadEmail = ref(contact.value?.email || '');
const leadPhone = ref(contact.value?.phone_number || '');
const savingLead = ref(false);
const orderNotes = ref('');
const savingOrder = ref(false);
const carts = ref([]);
const viewOptions = computed(() => [
  { id: 'profile', label: t('CONVERSATION_SIDEBAR.NERK.PROFILE_TAB') },
  { id: 'carts', label: t('CONVERSATION_SIDEBAR.NERK.CARTS_TAB') },
  { id: 'orders', label: t('CONVERSATION_SIDEBAR.NERK.ORDERS_TAB') },
]);
const orders = computed(() => context.value?.commerce?.orders || []);
const loyalty = computed(() => context.value?.commerce?.loyalty);
const wallet = computed(() => context.value?.commerce?.wallet);
const customer = computed(() => context.value?.customer);
const summary = computed(() => context.value?.summary || {});
const lastOrder = computed(() => orders.value[0]);
const activeCarts = computed(() =>
  carts.value.filter(cart => cart.status !== 'archived')
);
const archivedCarts = computed(() =>
  carts.value.filter(cart => cart.status === 'archived')
);
const activeCart = computed(() => activeCarts.value[0]);
const hasPendingDelivery = computed(() =>
  orders.value.some(order =>
    (order.shipping?.shipments || []).some(
      shipment => !['delivered', 'cancelled'].includes(shipment.status)
    )
  )
);

const formatCurrency = (amount, currency = 'BRL') =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency,
  }).format((amount || 0) / 100);

const formatUpdatedAt = value =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '—';

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

let refreshTimer;

const fetchContext = async (silent = false) => {
  if (!hasSearchableInfo.value) return;
  if (!silent) loading.value = true;
  error.value = '';
  identityRequired.value = false;
  try {
    const response = await NerkAPI.getContext(props.contactId);
    context.value = response.data.context;
  } catch (requestError) {
    identityRequired.value = requestError.response?.status === 409;
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    if (!silent) loading.value = false;
  }
};

const fetchCarts = async (silent = false) => {
  if (!hasSearchableInfo.value) return;
  if (!silent) loadingCarts.value = true;
  try {
    const response = await NerkAPI.getCarts(props.contactId);
    carts.value = response.data.carts || [];
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_LOAD_ERROR');
  } finally {
    if (!silent) loadingCarts.value = false;
  }
};

const refreshWorkspace = (silent = false) =>
  Promise.all([fetchContext(silent), fetchCarts(silent)]);

const refreshWhenVisible = () => {
  if (document.visibilityState === 'visible') refreshWorkspace(true);
};

const completeLead = async () => {
  savingLead.value = true;
  try {
    await NerkAPI.completeLead(props.contactId, {
      name: leadName.value,
      email: leadEmail.value,
      phone_number: leadPhone.value,
    });
    window.setTimeout(() => fetchContext(), 1000);
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    savingLead.value = false;
  }
};

const openOrder = order => {
  selectedOrder.value = order;
  orderNotes.value = order.notes || '';
  orderDialog.value?.open();
};

const saveOrder = async () => {
  savingOrder.value = true;
  try {
    await NerkAPI.updateOrder(
      props.contactId,
      selectedOrder.value.id,
      orderNotes.value
    );
    selectedOrder.value.notes = orderNotes.value;
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    savingOrder.value = false;
  }
};

const openNewOrder = cartId => {
  assistedSaleDialog.value?.open(cartId);
};

watch(
  () => props.contactId,
  () => refreshWorkspace(),
  { immediate: true }
);
onMounted(() => {
  refreshTimer = window.setInterval(() => {
    if (document.visibilityState === 'visible') refreshWorkspace(true);
  }, 30000);
  window.addEventListener('focus', refreshWhenVisible);
  document.addEventListener('visibilitychange', refreshWhenVisible);
});
onBeforeUnmount(() => {
  window.clearInterval(refreshTimer);
  window.removeEventListener('focus', refreshWhenVisible);
  document.removeEventListener('visibilitychange', refreshWhenVisible);
});
</script>

<template>
  <div class="p-3 text-n-slate-12">
    <div v-if="loading" class="flex justify-center p-4">
      <Spinner size="32" class="text-n-brand" />
    </div>
    <div v-else-if="error" class="flex flex-col gap-3">
      <p class="text-center text-sm text-n-ruby-11">{{ error }}</p>
      <form
        v-if="identityRequired"
        class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
        @submit.prevent="completeLead"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION_SIDEBAR.NERK.COMPLETE_LEAD') }}
        </p>
        <input
          v-model="leadName"
          required
          type="text"
          class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('CONVERSATION_SIDEBAR.NERK.LEAD_NAME')"
        />
        <input
          v-model="leadEmail"
          required
          type="email"
          class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('CONVERSATION_SIDEBAR.NERK.LEAD_EMAIL')"
        />
        <PhoneNumberInput
          v-model="leadPhone"
          :placeholder="t('CONVERSATION_SIDEBAR.NERK.LEAD_PHONE')"
        />
        <Button
          type="submit"
          color="blue"
          :disabled="!leadPhone"
          :is-loading="savingLead"
          :label="t('CONVERSATION_SIDEBAR.NERK.SAVE_LEAD')"
        />
      </form>
    </div>
    <p v-else-if="!hasSearchableInfo" class="text-center text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.NERK.MISSING_IDENTITY') }}
    </p>
    <div v-else class="flex flex-col gap-3">
      <div class="grid grid-cols-3 rounded-lg bg-n-alpha-2 p-1">
        <button
          v-for="view in viewOptions"
          :key="view.id"
          type="button"
          class="rounded-md px-3 py-2 text-xs font-medium"
          :class="
            activeView === view.id
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11'
          "
          @click="activeView = view.id"
        >
          {{ view.label }}
        </button>
      </div>

      <div
        v-if="activeView === 'profile' && (customer || loyalty)"
        class="flex flex-col gap-3"
      >
        <div class="rounded-lg bg-n-alpha-2 p-3">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ customer?.name }}
              </p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{ t('CONVERSATION_SIDEBAR.NERK.CUSTOMER_ID') }}
                {{ customer?.id }}
              </p>
            </div>
            <span class="rounded bg-n-teal-3 px-2 py-1 text-xs text-n-teal-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.IDENTITY_MATCHED') }}
            </span>
          </div>
          <p v-if="customer?.company_name" class="mt-2 text-xs text-n-slate-11">
            {{ customer.trade_name || customer.company_name }}
          </p>
          <div class="mt-3 grid grid-cols-2 gap-2 text-xs text-n-slate-11">
            <span>{{
              customer?.person_type === 'pj'
                ? t('CONVERSATION_SIDEBAR.NERK.PERSON_PJ')
                : t('CONVERSATION_SIDEBAR.NERK.PERSON_PF')
            }}</span>
            <span>{{
              customer?.document ||
              t('CONVERSATION_SIDEBAR.NERK.DOCUMENT_MISSING')
            }}</span>
            <span>{{ customer?.email }}</span>
            <span>{{
              customer?.phone || t('CONVERSATION_SIDEBAR.NERK.PHONE_MISSING')
            }}</span>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <div class="rounded-lg border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.LTV') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{ formatCurrency(customer?.lifetime_value_cents) }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{ loyalty?.points_balance || 0 }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.ORDER_COUNT') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{
                summary.paid_order_count ||
                summary.order_count_returned ||
                orders.length
              }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.PENDING_DELIVERY') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{
                hasPendingDelivery
                  ? t('CONVERSATION_SIDEBAR.NERK.YES')
                  : t('CONVERSATION_SIDEBAR.NERK.NO')
              }}
            </p>
          </div>
        </div>

        <button
          v-if="activeCart"
          type="button"
          class="rounded-xl border border-n-brand/40 bg-n-brand/5 p-3 text-left transition hover:border-n-brand hover:bg-n-brand/10"
          @click="openNewOrder(activeCart.id)"
        >
          <span class="flex items-start justify-between gap-3">
            <span>
              <span class="block text-xs font-medium text-n-brand">
                {{ t('CONVERSATION_SIDEBAR.NERK.SALE_IN_PROGRESS') }}
              </span>
              <span class="mt-1 block text-sm font-semibold text-n-slate-12">
                {{
                  t('CONVERSATION_SIDEBAR.NERK.CART_SUMMARY', {
                    items: t('CONVERSATION_SIDEBAR.NERK.CART_ITEMS_COUNT', {
                      count: activeCart.quote?.lines?.length || 0,
                    }),
                    total: formatCurrency(
                      activeCart.quote?.amounts?.estimated_total_cents
                    ),
                  })
                }}
              </span>
            </span>
            <span class="text-xs font-medium text-n-brand">
              {{ t('CONVERSATION_SIDEBAR.NERK.RESUME_SALE') }}
            </span>
          </span>
          <span class="mt-2 block text-[11px] text-n-slate-11">
            {{
              t('CONVERSATION_SIDEBAR.NERK.LAST_SYNC', {
                date: formatUpdatedAt(activeCart.updated_at),
              })
            }}
          </span>
        </button>

        <button
          v-if="lastOrder"
          type="button"
          class="flex items-center justify-between rounded-lg border border-n-weak p-3 text-left"
          @click="openOrder(lastOrder)"
        >
          <span>
            <span class="block text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.LAST_ORDER') }}
            </span>
            <span class="mt-1 block text-sm font-medium text-n-slate-12">
              {{
                t('CONVERSATION_SIDEBAR.NERK.ORDER_NUMBER', {
                  number: lastOrder.order_number,
                })
              }}
            </span>
          </span>
          <span class="text-xs text-n-slate-11">{{ lastOrder.status }}</span>
        </button>

        <div class="grid grid-cols-2 gap-2">
          <a
            v-if="context?.links?.customer"
            :href="context.links.customer"
            target="_blank"
            rel="noopener noreferrer"
            class="rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_PROFILE') }}
          </a>
          <button
            v-if="context?.links?.new_order"
            type="button"
            class="rounded-lg bg-n-brand px-3 py-2 text-center text-xs font-medium text-white"
            @click="openNewOrder()"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.NEW_ORDER') }}
          </button>
        </div>
      </div>

      <div v-if="activeView === 'carts'" class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-3">
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('CONVERSATION_SIDEBAR.NERK.CARTS_TITLE') }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.CARTS_DESCRIPTION') }}
            </p>
          </div>
          <button
            type="button"
            class="shrink-0 rounded-lg bg-n-brand px-3 py-2 text-xs font-medium text-white"
            @click="openNewOrder()"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.NEW_SALE') }}
          </button>
        </div>

        <div v-if="loadingCarts" class="flex justify-center p-4">
          <Spinner size="24" class="text-n-brand" />
        </div>
        <button
          v-else-if="activeCart"
          type="button"
          class="rounded-xl border border-n-brand/40 bg-n-brand/5 p-3 text-left"
          @click="openNewOrder(activeCart.id)"
        >
          <span class="flex items-start justify-between gap-2">
            <span>
              <span class="block text-xs font-medium text-n-brand">
                {{ t('CONVERSATION_SIDEBAR.NERK.ACTIVE_CART') }}
              </span>
              <span class="mt-1 block text-sm font-semibold text-n-slate-12">
                {{
                  formatCurrency(
                    activeCart.quote?.amounts?.estimated_total_cents
                  )
                }}
              </span>
            </span>
            <span class="text-xs font-medium text-n-brand">
              {{ t('CONVERSATION_SIDEBAR.NERK.RESUME_SALE') }}
            </span>
          </span>
          <span class="mt-2 block text-xs text-n-slate-11">
            {{
              t('CONVERSATION_SIDEBAR.NERK.CART_SYNC_SUMMARY', {
                items: t('CONVERSATION_SIDEBAR.NERK.CART_ITEMS_COUNT', {
                  count: activeCart.quote?.lines?.length || 0,
                }),
                date: formatUpdatedAt(activeCart.updated_at),
              })
            }}
          </span>
        </button>
        <div
          v-else-if="!loadingCarts"
          class="rounded-lg border border-dashed border-n-strong p-4 text-center"
        >
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.NO_OPEN_CART') }}
          </p>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.NERK.NO_OPEN_CART_DESCRIPTION') }}
          </p>
        </div>

        <div v-if="archivedCarts.length" class="border-t border-n-weak pt-3">
          <p
            class="mb-2 text-xs font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.CART_HISTORY') }}
          </p>
          <div class="flex flex-col gap-2">
            <div
              v-for="cart in archivedCarts.slice(0, 5)"
              :key="cart.id"
              class="rounded-lg border border-n-weak p-3"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="font-mono text-[11px] text-n-slate-11">
                  {{ cart.id.slice(0, 8) }}
                </span>
                <span class="text-xs font-medium text-n-slate-12">
                  {{
                    formatCurrency(cart.quote?.amounts?.estimated_total_cents)
                  }}
                </span>
              </div>
              <p class="mt-1 text-[11px] text-n-slate-10">
                {{
                  t('CONVERSATION_SIDEBAR.NERK.ARCHIVED_AT', {
                    date: formatUpdatedAt(cart.archived_at),
                  })
                }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <p
        v-if="activeView === 'orders' && !orders.length"
        class="text-center text-n-slate-11"
      >
        {{ t('CONVERSATION_SIDEBAR.NERK.NO_ORDERS') }}
      </p>
      <div
        v-else-if="activeView === 'orders'"
        class="flex flex-col divide-y divide-n-weak"
      >
        <article
          v-for="order in orders"
          :key="order.id"
          class="flex cursor-pointer flex-col gap-2 py-3"
          role="button"
          tabindex="0"
          @click="openOrder(order)"
          @keydown.enter="openOrder(order)"
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

    <Dialog
      ref="orderDialog"
      width="2xl"
      :title="
        selectedOrder
          ? t('CONVERSATION_SIDEBAR.NERK.ORDER_NUMBER', {
              number: selectedOrder.order_number,
            })
          : ''
      "
      :show-cancel-button="false"
      :show-confirm-button="false"
      overflow-y-auto
    >
      <div v-if="selectedOrder" class="flex max-h-[70vh] flex-col gap-5">
        <div class="grid grid-cols-2 gap-3">
          <div class="rounded-lg bg-n-alpha-2 p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.ORDER_STATUS') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{ selectedOrder.status }}
            </p>
          </div>
          <div class="rounded-lg bg-n-alpha-2 p-3">
            <p class="text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.ORDER_TOTAL') }}
            </p>
            <p class="mt-1 text-sm font-medium text-n-slate-12">
              {{
                formatCurrency(
                  selectedOrder.amounts.total_cents,
                  selectedOrder.amounts.currency
                )
              }}
            </p>
          </div>
        </div>

        <section>
          <h4 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.PRODUCTS') }}
          </h4>
          <div class="divide-y divide-n-weak rounded-lg border border-n-weak">
            <div
              v-for="item in selectedOrder.items"
              :key="`${item.sku}-${item.name}`"
              class="flex items-start justify-between gap-3 p-3"
            >
              <div>
                <p class="text-sm text-n-slate-12">{{ item.name }}</p>
                <p class="text-xs text-n-slate-11">
                  {{
                    t('CONVERSATION_SIDEBAR.NERK.ITEM_DETAIL', {
                      quantity: item.quantity,
                      sku: item.sku || '—',
                    })
                  }}
                </p>
              </div>
              <span class="text-sm text-n-slate-12">
                {{
                  formatCurrency(
                    item.total_cents || item.unit_price_cents * item.quantity,
                    selectedOrder.amounts.currency
                  )
                }}
              </span>
            </div>
          </div>
        </section>

        <section v-if="selectedOrder.shipping.shipments.length">
          <h4 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.TRACKING') }}
          </h4>
          <div class="flex flex-col gap-2">
            <div
              v-for="shipment in selectedOrder.shipping.shipments"
              :key="shipment.tracking_code || shipment.provider"
              class="rounded-lg border border-n-weak p-3"
            >
              <div class="flex items-center justify-between gap-3">
                <p class="text-sm font-medium text-n-slate-12">
                  {{ shipment.service || shipment.provider }}
                </p>
                <span class="text-xs text-n-slate-11">
                  {{ shipment.status }}
                </span>
              </div>
              <p class="mt-1 font-mono text-xs text-n-slate-11">
                {{ shipment.tracking_code || '—' }}
              </p>
            </div>
          </div>
        </section>

        <section v-if="selectedOrder.payments.length">
          <h4 class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.PAYMENTS') }}
          </h4>
          <div class="flex flex-col gap-2">
            <div
              v-for="(payment, index) in selectedOrder.payments"
              :key="`${payment.method}-${index}`"
              class="rounded-lg border border-n-weak p-3 text-sm text-n-slate-12"
            >
              <div class="flex justify-between gap-3">
                <span>
                  {{
                    t('CONVERSATION_SIDEBAR.NERK.PAYMENT_DETAIL', {
                      method: payment.method || '—',
                      status: payment.status,
                    })
                  }}
                </span>
                <span>
                  {{
                    formatCurrency(
                      payment.amount_cents,
                      selectedOrder.amounts.currency
                    )
                  }}
                </span>
              </div>
              <p
                v-if="payment.refunds.length"
                class="mt-2 text-xs text-n-ruby-11"
              >
                {{
                  t('CONVERSATION_SIDEBAR.NERK.REFUNDED', {
                    amount: formatCurrency(
                      payment.refunds.reduce(
                        (sum, refund) => sum + (refund.amount_cents || 0),
                        0
                      ),
                      selectedOrder.amounts.currency
                    ),
                  })
                }}
              </p>
            </div>
          </div>
        </section>

        <section>
          <label class="mb-2 block text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.ORDER_NOTES') }}
          </label>
          <textarea
            v-model="orderNotes"
            rows="4"
            maxlength="2000"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
          />
        </section>
      </div>
      <template #footer>
        <a
          v-if="selectedOrder?.backoffice_url"
          :href="selectedOrder.backoffice_url"
          target="_blank"
          rel="noopener noreferrer"
          class="rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-12"
        >
          {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_BACKOFFICE') }}
        </a>
        <Button
          color="blue"
          :is-loading="savingOrder"
          :label="t('CONVERSATION_SIDEBAR.NERK.SAVE_ORDER')"
          @click="saveOrder"
        />
        <Button
          color="slate"
          variant="faded"
          :label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
          @click="orderDialog?.close()"
        />
      </template>
    </Dialog>

    <NerkAssistedSaleDialog
      ref="assistedSaleDialog"
      :contact-id="contactId"
      :customer="customer"
      :loyalty="loyalty"
      :wallet="wallet"
      :profile-url="context?.links?.customer"
      @saved="refreshWorkspace(true)"
      @carts-updated="fetchCarts(true)"
    />
  </div>
</template>
