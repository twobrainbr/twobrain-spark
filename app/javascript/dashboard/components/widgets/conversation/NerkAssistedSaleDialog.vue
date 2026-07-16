<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import NerkAPI from 'dashboard/api/integrations/nerk';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  customer: {
    type: Object,
    default: null,
  },
  loyalty: {
    type: Object,
    default: null,
  },
  profileUrl: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();
const dialog = ref(null);
const query = ref('');
const products = ref([]);
const carts = ref([]);
const promotions = ref([]);
const lines = ref([]);
const currentCartId = ref(null);
const quote = ref(null);
const cartUrl = ref('');
const paymentUrl = ref('');
const backofficeUrl = ref('');
const couponCode = ref('');
const searching = ref(false);
const loadingCarts = ref(false);
const saving = ref(false);
const error = ref('');
const copied = ref('');
let searchTimer;

const clubEligible = computed(
  () => props.loyalty?.member && props.loyalty?.membership_status === 'active'
);
const amounts = computed(() => quote.value?.amounts || {});
const missingProfile = computed(() => {
  const fields = [];
  if (!props.customer?.name)
    fields.push(t('CONVERSATION_SIDEBAR.NERK.REQUIRED_NAME'));
  if (!props.customer?.email)
    fields.push(t('CONVERSATION_SIDEBAR.NERK.REQUIRED_EMAIL'));
  if (!props.customer?.phone)
    fields.push(t('CONVERSATION_SIDEBAR.NERK.REQUIRED_PHONE'));
  if (!props.customer?.document)
    fields.push(t('CONVERSATION_SIDEBAR.NERK.REQUIRED_DOCUMENT'));
  if (!props.customer?.addresses?.length)
    fields.push(t('CONVERSATION_SIDEBAR.NERK.REQUIRED_ADDRESS'));
  return fields;
});

const formatCurrency = amount =>
  new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'BRL',
  }).format((amount || 0) / 100);

const productImage = product => product.images?.[0]?.url || '';
const variantImage = (product, variant) =>
  variant.images?.[0]?.url || productImage(product);
const variantAttributes = variant =>
  (variant.attributes || []).map(attribute => attribute.value).join(' · ') ||
  variant.name;
const lineVariantAttributes = line =>
  (line.attributes || []).map(item => item.value).join(' · ') ||
  line.variantName ||
  line.variant_name;
const customerContact = computed(() =>
  [props.customer?.email, props.customer?.phone].filter(Boolean).join(' · ')
);
const productTaxonomy = product =>
  [product.brand?.name, product.category?.name].filter(Boolean).join(' · ');

const applyCart = cart => {
  currentCartId.value = cart.id;
  quote.value = cart.quote;
  lines.value = (cart.quote?.lines || []).map(line => ({ ...line }));
  couponCode.value = cart.quote?.coupon_code || '';
  cartUrl.value = cart.cart_url || '';
  paymentUrl.value = cart.payment_url || '';
  backofficeUrl.value = cart.backoffice_url || '';
};

const loadCarts = async (selectFirst = false) => {
  loadingCarts.value = true;
  try {
    const response = await NerkAPI.getCarts(props.contactId);
    carts.value = response.data.carts || [];
    if (selectFirst && carts.value.length) applyCart(carts.value[0]);
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_LOAD_ERROR');
  } finally {
    loadingCarts.value = false;
  }
};

const loadPromotions = async () => {
  try {
    const response = await NerkAPI.getPromotions();
    promotions.value = response.data.promotions || [];
  } catch {
    promotions.value = [];
  }
};

const searchProducts = async term => {
  searching.value = true;
  try {
    const response = await NerkAPI.searchProducts(term);
    products.value = response.data.products || [];
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.PRODUCT_SEARCH_ERROR');
  } finally {
    searching.value = false;
  }
};

watch(query, value => {
  window.clearTimeout(searchTimer);
  const term = value.trim();
  if (term.length < 2) {
    products.value = [];
    return;
  }
  searchTimer = window.setTimeout(() => searchProducts(term), 300);
});

const saveCart = async () => {
  if (!lines.value.length && !currentCartId.value) return;
  saving.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.createAssistedOrder(
      props.contactId,
      lines.value.map(line => ({
        variant_id: line.variantId || line.variant_id,
        quantity: line.quantity,
        pricing_mode: line.pricingMode || line.pricing_mode || 'official',
      })),
      couponCode.value,
      currentCartId.value
    );
    applyCart(response.data.assisted_order);
    await loadCarts();
    emit('saved');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};

const addVariant = async (product, variant) => {
  if (!variant.active || variant.stock < 1) return;
  const existing = lines.value.find(
    line => (line.variantId || line.variant_id) === variant.id
  );
  if (existing) existing.quantity += 1;
  else {
    lines.value.push({
      variantId: variant.id,
      productId: product.id,
      productName: product.name,
      variantName: variant.name,
      sku: variant.sku,
      imageUrl: variantImage(product, variant),
      stock: variant.stock,
      quantity: 1,
      pricingMode: 'official',
      referencePriceCents: variant.price_cents,
      officialPriceCents: variant.offer_price_cents,
      clubPriceCents: variant.club_price_cents,
      unitPriceCents: variant.offer_price_cents,
      promotionName: variant.promotion?.name,
      attributes: variant.attributes || [],
    });
  }
  await saveCart();
};

const changeQuantity = async (line, delta) => {
  const next = line.quantity + delta;
  if (next < 1) {
    lines.value = lines.value.filter(candidate => candidate !== line);
  } else if (next <= line.stock) line.quantity = next;
  else return;
  await saveCart();
};

const removeLine = async line => {
  lines.value = lines.value.filter(candidate => candidate !== line);
  await saveCart();
};

const setPricingMode = async (line, mode) => {
  if (mode === 'club' && !clubEligible.value) return;
  line.pricingMode = mode;
  line.pricing_mode = mode;
  await saveCart();
};

const startNewCart = () => {
  currentCartId.value = null;
  lines.value = [];
  quote.value = null;
  cartUrl.value = '';
  paymentUrl.value = '';
  backofficeUrl.value = '';
  couponCode.value = '';
  error.value = '';
};

const copyLink = async (type, value) => {
  await navigator.clipboard.writeText(value);
  copied.value = type;
  window.setTimeout(() => {
    copied.value = '';
  }, 1800);
};

const open = async () => {
  startNewCart();
  dialog.value?.open();
  await Promise.all([loadCarts(true), loadPromotions()]);
};

onBeforeUnmount(() => window.clearTimeout(searchTimer));
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="5xl"
    :title="t('CONVERSATION_SIDEBAR.NERK.ASSISTED_SALE_TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
  >
    <div class="flex max-h-[78vh] flex-col gap-4">
      <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-n-alpha-2 p-3"
      >
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ customer?.name }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ customerContact }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <span
            class="rounded-md px-2 py-1 text-xs"
            :class="
              clubEligible
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            {{
              clubEligible
                ? t('CONVERSATION_SIDEBAR.NERK.CLUB_ACTIVE')
                : t('CONVERSATION_SIDEBAR.NERK.CLUB_INACTIVE')
            }}
          </span>
          <span
            class="rounded-md px-2 py-1 text-xs"
            :class="
              missingProfile.length
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-teal-3 text-n-teal-11'
            "
          >
            {{
              missingProfile.length
                ? t('CONVERSATION_SIDEBAR.NERK.MISSING_FISCAL_DATA', {
                    count: missingProfile.length,
                  })
                : t('CONVERSATION_SIDEBAR.NERK.FISCAL_DATA_READY')
            }}
          </span>
        </div>
      </div>

      <div
        v-if="missingProfile.length"
        class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-amber-7 bg-n-amber-2 p-3 text-xs text-n-amber-11"
      >
        <span>
          {{
            t('CONVERSATION_SIDEBAR.NERK.MISSING_FIELDS', {
              fields: missingProfile.join(', '),
            })
          }}
        </span>
        <a
          v-if="profileUrl"
          :href="profileUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="rounded-lg border border-n-amber-7 bg-n-solid-1 px-3 py-2 font-medium text-n-amber-11"
        >
          {{ t('CONVERSATION_SIDEBAR.NERK.COMPLETE_REGISTRATION') }}
        </a>
      </div>
      <p v-if="error" class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11">
        {{ error }}
      </p>

      <div class="grid min-h-0 gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
        <section class="flex min-h-0 flex-col gap-3">
          <div class="flex items-center gap-2 overflow-x-auto pb-1">
            <button
              type="button"
              class="shrink-0 rounded-lg border border-n-weak px-3 py-2 text-xs font-medium text-n-slate-12"
              @click="startNewCart"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.NEW_CART') }}
            </button>
            <Spinner v-if="loadingCarts" size="18" class="text-n-brand" />
            <button
              v-for="cart in carts"
              :key="cart.id"
              type="button"
              class="shrink-0 rounded-lg border px-3 py-2 text-left text-xs"
              :class="
                currentCartId === cart.id
                  ? 'border-n-brand bg-n-brand/10 text-n-brand'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="applyCart(cart)"
            >
              <span class="block font-medium">{{
                t('CONVERSATION_SIDEBAR.NERK.CART_SHORT', {
                  id: cart.id.slice(0, 8),
                })
              }}</span>
              <span>{{
                formatCurrency(cart.quote?.amounts?.estimated_total_cents)
              }}</span>
            </button>
          </div>

          <div class="relative">
            <input
              v-model="query"
              type="search"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-4 py-3 pr-10 text-sm text-n-slate-12"
              :placeholder="t('CONVERSATION_SIDEBAR.NERK.LIVE_PRODUCT_SEARCH')"
            />
            <Spinner
              v-if="searching"
              size="18"
              class="absolute right-3 top-3 text-n-brand"
            />
          </div>

          <div v-if="promotions.length" class="flex gap-2 overflow-x-auto pb-1">
            <button
              v-for="promotion in promotions"
              :key="promotion.code"
              type="button"
              class="shrink-0 rounded-lg border border-n-weak bg-n-alpha-2 px-3 py-2 text-left text-xs"
              :disabled="saving"
              @click="
                couponCode = promotion.code;
                saveCart();
              "
            >
              <span class="block font-medium text-n-slate-12">{{
                promotion.code
              }}</span>
              <span class="text-n-slate-11">{{
                promotion.description ||
                t('CONVERSATION_SIDEBAR.NERK.AVAILABLE_COUPON')
              }}</span>
            </button>
          </div>

          <div class="min-h-0 flex-1 space-y-3 overflow-y-auto pr-1">
            <article
              v-for="product in products"
              :key="product.id"
              class="rounded-lg border border-n-weak p-3"
            >
              <div class="flex gap-3">
                <img
                  :src="productImage(product)"
                  :alt="product.name"
                  class="size-16 rounded-lg border border-n-weak object-cover"
                />
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-n-slate-12">
                    {{ product.name }}
                  </p>
                  <p class="text-xs text-n-slate-11">
                    {{ productTaxonomy(product) }}
                  </p>
                </div>
              </div>
              <div class="mt-3 grid gap-2 sm:grid-cols-2">
                <button
                  v-for="variant in product.variants"
                  :key="variant.id"
                  type="button"
                  class="flex items-center gap-2 rounded-lg border border-n-weak p-2 text-left disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="!variant.active || variant.stock < 1 || saving"
                  @click="addVariant(product, variant)"
                >
                  <img
                    :src="variantImage(product, variant)"
                    :alt="variant.name"
                    class="size-10 rounded-md object-cover"
                  />
                  <span class="min-w-0 flex-1">
                    <span
                      class="block truncate text-xs font-medium text-n-slate-12"
                    >
                      {{ variantAttributes(variant) }}
                    </span>
                    <span class="block text-[11px] text-n-slate-11">
                      {{
                        t('CONVERSATION_SIDEBAR.NERK.VARIANT_STOCK', {
                          sku: variant.sku,
                          count: variant.stock,
                        })
                      }}
                    </span>
                    <span
                      v-if="variant.promotion"
                      class="block text-[11px] text-n-teal-11"
                    >
                      {{ variant.promotion.name }}
                    </span>
                  </span>
                  <span class="text-right text-xs">
                    <span class="block font-medium text-n-slate-12">{{
                      formatCurrency(variant.offer_price_cents)
                    }}</span>
                    <span v-if="clubEligible" class="block text-n-teal-11">{{
                      formatCurrency(variant.club_price_cents)
                    }}</span>
                  </span>
                </button>
              </div>
            </article>
            <p
              v-if="query.trim().length >= 2 && !searching && !products.length"
              class="py-8 text-center text-sm text-n-slate-11"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.NO_PRODUCTS_FOUND') }}
            </p>
          </div>
        </section>

        <aside
          class="flex min-h-0 flex-col rounded-lg border border-n-weak bg-n-solid-1"
        >
          <div class="border-b border-n-weak p-4">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION_SIDEBAR.NERK.CART_TITLE') }}
              </h4>
              <Spinner v-if="saving" size="18" class="text-n-brand" />
            </div>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.CART_AUTOSAVE') }}
            </p>
          </div>

          <div class="min-h-0 flex-1 divide-y divide-n-weak overflow-y-auto">
            <div
              v-for="line in lines"
              :key="line.variantId || line.variant_id"
              class="p-3"
            >
              <div class="flex gap-2">
                <img
                  :src="line.imageUrl || line.image_url"
                  :alt="line.productName || line.product_name"
                  class="size-12 rounded-md object-cover"
                />
                <div class="min-w-0 flex-1">
                  <p class="truncate text-xs font-medium text-n-slate-12">
                    {{ line.productName || line.product_name }}
                  </p>
                  <p class="truncate text-[11px] text-n-slate-11">
                    {{ lineVariantAttributes(line) }}
                  </p>
                  <p class="text-[11px] text-n-slate-11">{{ line.sku }}</p>
                </div>
                <button
                  type="button"
                  class="self-start text-xs text-n-ruby-11"
                  :aria-label="t('CONVERSATION_SIDEBAR.NERK.REMOVE_ITEM')"
                  :disabled="saving"
                  @click="removeLine(line)"
                >
                  {{ t('CONVERSATION_SIDEBAR.NERK.REMOVE_SYMBOL') }}
                </button>
              </div>
              <div class="mt-2 flex items-center justify-between gap-2">
                <div class="flex items-center rounded-md border border-n-weak">
                  <button
                    type="button"
                    class="px-2 py-1 text-sm"
                    :aria-label="
                      t('CONVERSATION_SIDEBAR.NERK.DECREASE_QUANTITY')
                    "
                    :disabled="saving"
                    @click="changeQuantity(line, -1)"
                  >
                    {{ t('CONVERSATION_SIDEBAR.NERK.DECREASE_SYMBOL') }}
                  </button>
                  <span class="min-w-7 text-center text-xs">{{
                    line.quantity
                  }}</span>
                  <button
                    type="button"
                    class="px-2 py-1 text-sm"
                    :aria-label="
                      t('CONVERSATION_SIDEBAR.NERK.INCREASE_QUANTITY')
                    "
                    :disabled="saving"
                    @click="changeQuantity(line, 1)"
                  >
                    {{ t('CONVERSATION_SIDEBAR.NERK.INCREASE_SYMBOL') }}
                  </button>
                </div>
                <span class="text-xs font-medium text-n-slate-12">{{
                  formatCurrency(
                    (line.unitPriceCents || line.unit_price_cents) *
                      line.quantity
                  )
                }}</span>
              </div>
              <div
                class="mt-2 grid grid-cols-2 gap-1 rounded-md bg-n-alpha-2 p-1"
              >
                <button
                  type="button"
                  class="rounded px-2 py-1 text-[11px]"
                  :class="
                    (line.pricingMode || line.pricing_mode) !== 'club'
                      ? 'bg-n-solid-1 text-n-slate-12'
                      : 'text-n-slate-11'
                  "
                  :disabled="saving"
                  @click="setPricingMode(line, 'official')"
                >
                  {{ t('CONVERSATION_SIDEBAR.NERK.REGULAR_PRICE') }}
                </button>
                <button
                  type="button"
                  class="rounded px-2 py-1 text-[11px]"
                  :class="
                    (line.pricingMode || line.pricing_mode) === 'club'
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'text-n-slate-11'
                  "
                  :disabled="!clubEligible || saving"
                  @click="setPricingMode(line, 'club')"
                >
                  {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_PRICE') }}
                </button>
              </div>
            </div>
            <p
              v-if="!lines.length"
              class="p-8 text-center text-sm text-n-slate-11"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.EMPTY_CART') }}
            </p>
          </div>

          <div class="border-t border-n-weak p-4">
            <div class="flex gap-2">
              <input
                v-model="couponCode"
                type="text"
                class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs uppercase"
                :placeholder="t('CONVERSATION_SIDEBAR.NERK.COUPON_CODE')"
              />
              <button
                type="button"
                class="rounded-lg border border-n-weak px-3 py-2 text-xs font-medium"
                :disabled="!lines.length || saving"
                @click="saveCart"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.APPLY') }}
              </button>
            </div>
            <dl v-if="quote" class="mt-3 space-y-1.5 text-xs">
              <div class="flex justify-between">
                <dt class="text-n-slate-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.SUBTOTAL') }}
                </dt>
                <dd>{{ formatCurrency(amounts.subtotal_cents) }}</dd>
              </div>
              <div
                v-if="amounts.discount_cents"
                class="flex justify-between text-n-teal-11"
              >
                <dt>{{ t('CONVERSATION_SIDEBAR.NERK.DISCOUNT') }}</dt>
                <dd>
                  {{
                    t('CONVERSATION_SIDEBAR.NERK.NEGATIVE_AMOUNT', {
                      amount: formatCurrency(amounts.discount_cents),
                    })
                  }}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-n-slate-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.ESTIMATED_SHIPPING') }}
                </dt>
                <dd>{{ formatCurrency(amounts.estimated_shipping_cents) }}</dd>
              </div>
              <div
                class="flex justify-between border-t border-n-weak pt-2 text-sm font-medium"
              >
                <dt>{{ t('CONVERSATION_SIDEBAR.NERK.ESTIMATED_TOTAL') }}</dt>
                <dd>{{ formatCurrency(amounts.estimated_total_cents) }}</dd>
              </div>
            </dl>
            <div v-if="cartUrl" class="mt-3 grid grid-cols-2 gap-2">
              <button
                type="button"
                class="rounded-lg border border-n-weak px-3 py-2 text-xs font-medium text-n-slate-12"
                @click="copyLink('cart', cartUrl)"
              >
                {{
                  copied === 'cart'
                    ? t('CONVERSATION_SIDEBAR.NERK.COPIED')
                    : t('CONVERSATION_SIDEBAR.NERK.COPY_CART_LINK')
                }}
              </button>
              <button
                type="button"
                class="rounded-lg bg-n-brand px-3 py-2 text-xs font-medium text-white"
                @click="copyLink('payment', paymentUrl)"
              >
                {{
                  copied === 'payment'
                    ? t('CONVERSATION_SIDEBAR.NERK.COPIED')
                    : t('CONVERSATION_SIDEBAR.NERK.COPY_PAYMENT_LINK')
                }}
              </button>
              <a
                v-if="backofficeUrl"
                :href="backofficeUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="col-span-2 rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_BACKOFFICE') }}
              </a>
            </div>
          </div>
        </aside>
      </div>
    </div>
    <template #footer>
      <Button
        color="slate"
        variant="faded"
        :label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
        @click="dialog?.close()"
      />
    </template>
  </Dialog>
</template>
