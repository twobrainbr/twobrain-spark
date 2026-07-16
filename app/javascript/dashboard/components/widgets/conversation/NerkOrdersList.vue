<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import NerkAPI from 'dashboard/api/integrations/nerk';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

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
const newOrderDialog = ref(null);
const selectedOrder = ref(null);
const activeView = ref('profile');
const loading = ref(false);
const error = ref('');
const orderNotes = ref('');
const savingOrder = ref(false);
const productQuery = ref('');
const productResults = ref([]);
const searchingProducts = ref(false);
const cartLines = ref([]);
const couponCode = ref('');
const creatingOrder = ref(false);
const assistedOrder = ref(null);
const viewOptions = computed(() => [
  { id: 'profile', label: t('CONVERSATION_SIDEBAR.NERK.PROFILE_TAB') },
  { id: 'orders', label: t('CONVERSATION_SIDEBAR.NERK.ORDERS_TAB') },
]);
const orders = computed(() => context.value?.commerce?.orders || []);
const loyalty = computed(() => context.value?.commerce?.loyalty);
const customer = computed(() => context.value?.customer);
const summary = computed(() => context.value?.summary || {});
const lastOrder = computed(() => orders.value[0]);
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
  try {
    const response = await NerkAPI.getContext(props.contactId);
    context.value = response.data.context;
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    if (!silent) loading.value = false;
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

const searchProducts = async () => {
  if (productQuery.value.trim().length < 2) return;
  searchingProducts.value = true;
  try {
    const response = await NerkAPI.searchProducts(productQuery.value.trim());
    productResults.value = response.data.products || [];
  } finally {
    searchingProducts.value = false;
  }
};

const addVariant = (product, variant) => {
  const existing = cartLines.value.find(line => line.variantId === variant.id);
  if (existing) existing.quantity += 1;
  else {
    cartLines.value.push({
      variantId: variant.id,
      name: `${product.name}${variant.name && variant.name !== 'Padrão' ? ` — ${variant.name}` : ''}`,
      sku: variant.sku,
      priceCents: variant.price_cents,
      quantity: 1,
    });
  }
};

const createAssistedOrder = async () => {
  if (!cartLines.value.length) return;
  creatingOrder.value = true;
  try {
    const response = await NerkAPI.createAssistedOrder(
      props.contactId,
      cartLines.value.map(line => ({
        variant_id: line.variantId,
        quantity: line.quantity,
      })),
      couponCode.value
    );
    assistedOrder.value = response.data.assisted_order;
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.ERROR');
  } finally {
    creatingOrder.value = false;
  }
};

const openNewOrder = () => {
  assistedOrder.value = null;
  cartLines.value = [];
  productResults.value = [];
  productQuery.value = '';
  couponCode.value = '';
  newOrderDialog.value?.open();
};

watch(
  () => props.contactId,
  () => fetchContext(),
  { immediate: true }
);
onMounted(() => {
  refreshTimer = window.setInterval(() => fetchContext(true), 30000);
});
onBeforeUnmount(() => window.clearInterval(refreshTimer));
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
      <div class="grid grid-cols-2 rounded-lg bg-n-alpha-2 p-1">
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
            @click="openNewOrder"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.NEW_ORDER') }}
          </button>
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

    <Dialog
      ref="newOrderDialog"
      width="2xl"
      :title="t('CONVERSATION_SIDEBAR.NERK.NEW_ORDER')"
      :show-cancel-button="false"
      :show-confirm-button="false"
      overflow-y-auto
    >
      <div class="flex max-h-[70vh] flex-col gap-4">
        <div v-if="assistedOrder" class="rounded-lg bg-n-teal-3 p-4">
          <p class="text-sm font-medium text-n-teal-11">
            {{ t('CONVERSATION_SIDEBAR.NERK.PAYMENT_LINK_READY') }}
          </p>
          <a
            :href="assistedOrder.payment_url"
            target="_blank"
            rel="noopener noreferrer"
            class="mt-2 block break-all text-sm text-n-brand underline"
          >
            {{ assistedOrder.payment_url }}
          </a>
          <a
            :href="assistedOrder.backoffice_url"
            target="_blank"
            rel="noopener noreferrer"
            class="mt-3 inline-block rounded-lg border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_BACKOFFICE') }}
          </a>
        </div>

        <template v-else>
          <div class="flex gap-2">
            <input
              v-model="productQuery"
              type="search"
              class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
              :placeholder="t('CONVERSATION_SIDEBAR.NERK.PRODUCT_SEARCH')"
              @keydown.enter="searchProducts"
            />
            <button
              type="button"
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white"
              :disabled="searchingProducts"
              @click="searchProducts"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.SEARCH') }}
            </button>
          </div>

          <div
            v-if="productResults.length"
            class="divide-y divide-n-weak rounded-lg border border-n-weak"
          >
            <div
              v-for="product in productResults"
              :key="product.id"
              class="p-3"
            >
              <p class="text-sm font-medium text-n-slate-12">
                {{ product.name }}
              </p>
              <button
                v-for="variant in product.variants"
                :key="variant.id"
                type="button"
                class="mt-2 flex w-full justify-between rounded-lg bg-n-alpha-2 px-3 py-2 text-left text-xs"
                @click="addVariant(product, variant)"
              >
                <span>{{ `${variant.name} · ${variant.sku}` }}</span>
                <span>{{ formatCurrency(variant.price_cents) }}</span>
              </button>
            </div>
          </div>

          <div
            v-if="cartLines.length"
            class="divide-y divide-n-weak rounded-lg border border-n-weak"
          >
            <div
              v-for="line in cartLines"
              :key="line.variantId"
              class="flex items-center gap-3 p-3"
            >
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm text-n-slate-12">{{ line.name }}</p>
                <p class="text-xs text-n-slate-11">
                  {{ `${line.sku} · ${formatCurrency(line.priceCents)}` }}
                </p>
              </div>
              <input
                v-model.number="line.quantity"
                type="number"
                min="1"
                class="w-16 rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm"
              />
            </div>
          </div>

          <input
            v-model="couponCode"
            type="text"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
            :placeholder="t('CONVERSATION_SIDEBAR.NERK.COUPON_CODE')"
          />
        </template>
      </div>
      <template #footer>
        <Button
          v-if="!assistedOrder"
          color="blue"
          :is-loading="creatingOrder"
          :disabled="!cartLines.length"
          :label="t('CONVERSATION_SIDEBAR.NERK.CREATE_PAYMENT_LINK')"
          @click="createAssistedOrder"
        />
        <Button
          color="slate"
          variant="faded"
          :label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
          @click="newOrderDialog?.close()"
        />
      </template>
    </Dialog>
  </div>
</template>
