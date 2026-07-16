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
  wallet: {
    type: Object,
    default: null,
  },
  profileUrl: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['saved', 'cartsUpdated']);
const { t } = useI18n();
const dialog = ref(null);
const nerkLogoUrl = ['/dashboard', 'images', 'integrations', 'nerk.svg'].join(
  '/'
);
const flowStep = ref('carts');
const query = ref('');
const products = ref([]);
const selectedVariantIds = ref({});
const carts = ref([]);
const promotions = ref([]);
const combos = ref([]);
const lines = ref([]);
const currentCartId = ref(null);
const quote = ref(null);
const cartUrl = ref('');
const paymentUrl = ref('');
const backofficeUrl = ref('');
const couponCode = ref('');
const cartPricingMode = ref('official');
const searching = ref(false);
const loadingCarts = ref(false);
const saving = ref(false);
const error = ref('');
const copied = ref('');
const lastSavedAt = ref(null);
const profileOpen = ref(false);
const redeemPoints = ref(0);
const redeeming = ref(false);
const redeemedPointsBalance = ref(null);
const redeemedWalletBalance = ref(null);
let searchTimer;

const clubEligible = computed(
  () => props.loyalty?.member && props.loyalty?.membership_status === 'active'
);
const pointsBalance = computed(
  () => redeemedPointsBalance.value ?? props.loyalty?.points_balance ?? 0
);
const walletBalance = computed(
  () => redeemedWalletBalance.value ?? props.wallet?.balance_cents ?? 0
);
const redemption = computed(() => props.loyalty?.redemption || {});
const pointValueCents = computed(
  () => redemption.value.redeem_value_cents_per_point || 0
);
const redeemableValue = computed(
  () => pointsBalance.value * pointValueCents.value
);
const minRedeemPoints = computed(() => redemption.value.min_redeem_points || 1);
const customerInitials = computed(() =>
  (props.customer?.name || 'NERK')
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part.charAt(0))
    .join('')
    .toUpperCase()
);
const amounts = computed(() => quote.value?.amounts || {});
const cartSyncLabel = computed(() => {
  if (saving.value) return t('CONVERSATION_SIDEBAR.NERK.SAVING_CART');
  if (!lastSavedAt.value) return t('CONVERSATION_SIDEBAR.NERK.CART_AUTOSAVE');

  return t('CONVERSATION_SIDEBAR.NERK.CART_SAVED_AT', {
    date: new Intl.DateTimeFormat(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    }).format(new Date(lastSavedAt.value)),
  });
});
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
const variantOptionLabel = variant =>
  [
    variantAttributes(variant),
    formatCurrency(variant.offer_price_cents),
    t('CONVERSATION_SIDEBAR.NERK.STOCK_COUNT', { count: variant.stock }),
  ].join(' · ');
const lineVariantAttributes = line =>
  (line.attributes || []).map(item => item.value).join(' · ') ||
  line.variantName ||
  line.variant_name;
const registrationUrl = computed(() => {
  if (!props.profileUrl) return '';
  const separator = props.profileUrl.includes('?') ? '&' : '?';
  const section = props.customer?.addresses?.length ? 'fiscal' : 'addresses';
  return `${props.profileUrl}${separator}atendimento=1&etapa=${section}`;
});
const profileSectionUrl = section => {
  if (!props.profileUrl) return '';
  const separator = props.profileUrl.includes('?') ? '&' : '?';
  return `${props.profileUrl}${separator}atendimento=1&etapa=${section}`;
};
const redeemPreview = computed(() =>
  formatCurrency(Number(redeemPoints.value || 0) * pointValueCents.value)
);
const productTaxonomy = product =>
  [product.brand?.name, product.category?.name].filter(Boolean).join(' · ');
const availableVariants = product =>
  (product.variants || []).filter(
    variant => variant.active && variant.stock > 0
  );
const selectedVariant = product => {
  const available = availableVariants(product);
  const selectedId = selectedVariantIds.value[product.id];
  return available.find(variant => variant.id === selectedId) || available[0];
};
const comboImages = combo =>
  (combo.items || [])
    .map(item => productImage(item.product || {}))
    .filter(Boolean)
    .slice(0, 3);
const lineCombo = line =>
  combos.value.find(combo => combo.id === (line.comboId || line.combo_id));

const applyCart = cart => {
  currentCartId.value = cart.id;
  quote.value = cart.quote;
  lines.value = (cart.quote?.lines || []).map(line => ({ ...line }));
  cartPricingMode.value =
    lines.value.length &&
    lines.value.every(
      line => (line.pricingMode || line.pricing_mode) === 'club'
    )
      ? 'club'
      : 'official';
  couponCode.value = cart.quote?.coupon_code || '';
  cartUrl.value = cart.cart_url || '';
  paymentUrl.value = cart.payment_url || '';
  backofficeUrl.value = cart.backoffice_url || '';
  lastSavedAt.value = cart.updated_at || new Date().toISOString();
};

const loadCarts = async () => {
  loadingCarts.value = true;
  try {
    const response = await NerkAPI.getCarts(props.contactId);
    carts.value = (response.data.carts || []).filter(
      cart => cart.status !== 'archived'
    );
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
    combos.value = response.data.combos || [];
  } catch {
    promotions.value = [];
    combos.value = [];
  }
};

const searchProducts = async term => {
  searching.value = true;
  try {
    const response = await NerkAPI.searchProducts(term);
    products.value = response.data.products || [];
    products.value.forEach(product => {
      if (!selectedVariantIds.value[product.id]) {
        selectedVariantIds.value[product.id] =
          availableVariants(product)[0]?.id;
      }
    });
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
    emit('cartsUpdated');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};

const addCombo = async combo => {
  (combo.items || []).forEach(item => {
    const product = item.product;
    const variant =
      product?.variants?.find(candidate => candidate.id === item.variant_id) ||
      product?.variants?.find(candidate => candidate.active && candidate.stock);
    if (!product || !variant) return;
    const existing = lines.value.find(
      line => (line.variantId || line.variant_id) === variant.id
    );
    if (existing) existing.quantity += item.required_quantity || 1;
    else {
      lines.value.push({
        variantId: variant.id,
        productId: product.id,
        productName: product.name,
        variantName: variant.name,
        sku: variant.sku,
        imageUrl: variantImage(product, variant),
        stock: variant.stock,
        quantity: item.required_quantity || 1,
        pricingMode: cartPricingMode.value,
        referencePriceCents: variant.price_cents,
        officialPriceCents: variant.offer_price_cents,
        clubPriceCents: variant.club_price_cents,
        unitPriceCents: variant.offer_price_cents,
        promotionName: variant.promotion?.name,
        attributes: variant.attributes || [],
      });
    }
  });
  await saveCart();
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
      pricingMode: cartPricingMode.value,
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

const addSelectedVariant = product => {
  const variant = selectedVariant(product);
  if (variant) addVariant(product, variant);
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

const setCartPricingMode = async mode => {
  if (mode === 'club' && !clubEligible.value) return;
  cartPricingMode.value = mode;
  lines.value.forEach(line => {
    line.pricingMode = mode;
    line.pricing_mode = mode;
  });
  if (lines.value.length) await saveCart();
};

const resetCart = () => {
  currentCartId.value = null;
  lines.value = [];
  quote.value = null;
  cartUrl.value = '';
  paymentUrl.value = '';
  backofficeUrl.value = '';
  couponCode.value = '';
  query.value = '';
  products.value = [];
  lastSavedAt.value = null;
  error.value = '';
};

const selectCart = async cart => {
  applyCart(cart);
  flowStep.value = 'pdv';
  if (!promotions.value.length) await loadPromotions();
  await searchProducts(query.value.trim());
};

const startNewCart = async () => {
  saving.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.startNewCart(props.contactId);
    applyCart(response.data.cart);
    carts.value = [response.data.cart];
    flowStep.value = 'pdv';
    await loadPromotions();
    await searchProducts(query.value.trim());
    emit('saved');
    emit('cartsUpdated');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_CREATE_ERROR');
  } finally {
    saving.value = false;
  }
};

const copyLink = async (type, value) => {
  await navigator.clipboard.writeText(value);
  copied.value = type;
  window.setTimeout(() => {
    copied.value = '';
  }, 1800);
};

const redeemLoyalty = async () => {
  redeeming.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.redeemLoyalty(
      props.contactId,
      Number(redeemPoints.value)
    );
    const result = response.data.redemption;
    redeemedPointsBalance.value = result.points_balance;
    redeemedWalletBalance.value = result.wallet_balance_cents;
    redeemPoints.value = 0;
    emit('saved');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.REDEEM_ERROR');
  } finally {
    redeeming.value = false;
  }
};

const open = async cartId => {
  resetCart();
  flowStep.value = 'carts';
  profileOpen.value = false;
  redeemedPointsBalance.value = null;
  redeemedWalletBalance.value = null;
  dialog.value?.open();
  await loadCarts();
  const cart = carts.value.find(candidate => candidate.id === cartId);
  if (cart) await selectCart(cart);
};

onBeforeUnmount(() => window.clearTimeout(searchTimer));
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="panel"
    position="right"
    :title="t('CONVERSATION_SIDEBAR.NERK.ASSISTED_SALE_TITLE')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    prevent-close
  >
    <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-hidden">
      <div
        class="relative flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 shadow-sm"
      >
        <img
          :src="nerkLogoUrl"
          :alt="t('CONVERSATION_SIDEBAR.NERK.BRAND_LOGO')"
          class="h-7 w-auto rounded-md"
        />
        <span class="hidden h-7 w-px bg-n-weak sm:block" />
        <div class="flex min-w-0 flex-1 items-center gap-2 overflow-x-auto">
          <button
            type="button"
            class="flex shrink-0 items-center gap-2 rounded-lg bg-n-teal-3 px-3 py-1.5 text-left hover:bg-n-teal-4"
            @click="profileOpen = true"
          >
            <span class="i-lucide-wallet size-4 text-n-teal-11" />
            <span>
              <span class="block text-[10px] text-n-teal-11">{{
                t('CONVERSATION_SIDEBAR.NERK.WALLET_BALANCE')
              }}</span>
              <span class="block text-xs font-semibold text-n-teal-12">{{
                formatCurrency(walletBalance)
              }}</span>
            </span>
          </button>
          <button
            type="button"
            class="flex shrink-0 items-center gap-2 rounded-lg bg-n-amber-3 px-3 py-1.5 text-left hover:bg-n-amber-4"
            @click="profileOpen = true"
          >
            <span class="i-lucide-sparkles size-4 text-n-amber-11" />
            <span>
              <span class="block text-[10px] text-n-amber-11">{{
                t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS')
              }}</span>
              <span class="block text-xs font-semibold text-n-amber-12">
                {{ pointsBalance }} · {{ formatCurrency(redeemableValue) }}
              </span>
            </span>
          </button>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <button
            type="button"
            class="flex items-center gap-2 rounded-lg p-1 pr-2 text-left hover:bg-n-alpha-2"
            @click="profileOpen = !profileOpen"
          >
            <span
              class="flex size-8 items-center justify-center rounded-full bg-n-brand text-xs font-semibold text-white"
              >{{ customerInitials }}</span
            >
            <span
              class="hidden max-w-28 truncate text-xs font-medium text-n-slate-12 xl:block"
            >
              {{ customer?.name }}
            </span>
            <span class="i-lucide-chevron-down size-3 text-n-slate-10" />
          </button>
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 text-base text-n-slate-11 hover:text-n-slate-12"
            :aria-label="t('CONVERSATION_SIDEBAR.NERK.CLOSE_PDV')"
            @click="dialog?.close()"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.REMOVE_SYMBOL') }}
          </button>
        </div>

        <div
          v-if="profileOpen"
          class="absolute right-3 top-[calc(100%+0.5rem)] z-30 flex max-h-[calc(100vh-8rem)] w-[min(24rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-xl"
        >
          <div class="flex items-start gap-3 border-b border-n-weak p-4">
            <span
              class="flex size-11 shrink-0 items-center justify-center rounded-full bg-n-brand text-sm font-semibold text-white"
              >{{ customerInitials }}</span
            >
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-semibold text-n-slate-12">
                {{ customer?.name }}
              </p>
              <a
                v-if="customer?.email"
                :href="`mailto:${customer.email}`"
                class="block truncate text-xs text-n-brand hover:underline"
                >{{ customer.email }}</a
              >
              <a
                v-if="customer?.phone"
                :href="`tel:${customer.phone}`"
                class="block truncate text-xs text-n-brand hover:underline"
                >{{ customer.phone }}</a
              >
            </div>
            <button
              type="button"
              class="i-lucide-x size-4 text-n-slate-10 hover:text-n-slate-12"
              :aria-label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
              @click="profileOpen = false"
            />
          </div>

          <div class="space-y-3 overflow-y-auto p-4">
            <div class="grid grid-cols-2 gap-2">
              <div class="rounded-lg bg-n-teal-3 p-3">
                <p class="text-[10px] uppercase tracking-wide text-n-teal-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.WALLET_BALANCE') }}
                </p>
                <p class="mt-1 text-base font-semibold text-n-teal-12">
                  {{ formatCurrency(walletBalance) }}
                </p>
                <p class="text-[11px] text-n-teal-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.WALLET_CHECKOUT_HELP') }}
                </p>
              </div>
              <div class="rounded-lg bg-n-amber-3 p-3">
                <p class="text-[10px] uppercase tracking-wide text-n-amber-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS') }}
                </p>
                <p class="mt-1 text-base font-semibold text-n-amber-12">
                  {{ pointsBalance }}
                </p>
                <p class="text-[11px] text-n-amber-11">
                  {{
                    t('CONVERSATION_SIDEBAR.NERK.POINTS_WORTH', {
                      value: formatCurrency(redeemableValue),
                    })
                  }}
                </p>
              </div>
            </div>

            <form
              v-if="clubEligible && pointValueCents"
              class="rounded-lg border border-n-weak p-3"
              @submit.prevent="redeemLoyalty"
            >
              <div class="flex items-end gap-2">
                <label class="min-w-0 flex-1 text-xs text-n-slate-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.CONVERT_POINTS') }}
                  <input
                    v-model.number="redeemPoints"
                    type="number"
                    :min="minRedeemPoints"
                    :max="pointsBalance"
                    step="1"
                    class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
                  />
                </label>
                <Button
                  type="submit"
                  size="sm"
                  color="blue"
                  :disabled="
                    redeemPoints < minRedeemPoints ||
                    redeemPoints > pointsBalance
                  "
                  :is-loading="redeeming"
                  :label="
                    t('CONVERSATION_SIDEBAR.NERK.CONVERT_VALUE', {
                      value: redeemPreview,
                    })
                  "
                />
              </div>
              <p class="mt-2 text-[11px] text-n-slate-10">
                {{
                  t('CONVERSATION_SIDEBAR.NERK.MIN_REDEEM', {
                    count: minRedeemPoints,
                  })
                }}
              </p>
            </form>

            <div class="grid grid-cols-2 gap-2">
              <a
                v-if="profileUrl"
                :href="profileSectionUrl('fiscal')"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
                >{{ t('CONVERSATION_SIDEBAR.NERK.EDIT_PROFILE') }}</a
              >
              <a
                v-if="profileUrl"
                :href="profileSectionUrl('contacts')"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
                >{{ t('CONVERSATION_SIDEBAR.NERK.ADD_CONTACT') }}</a
              >
              <a
                v-if="profileUrl"
                :href="profileSectionUrl('fiscal')"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
                >{{ t('CONVERSATION_SIDEBAR.NERK.EDIT_FISCAL') }}</a
              >
              <a
                v-if="profileUrl"
                :href="profileSectionUrl('addresses')"
                target="_blank"
                rel="noopener noreferrer"
                class="rounded-lg border border-n-weak px-3 py-2 text-center text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2"
                >{{ t('CONVERSATION_SIDEBAR.NERK.MANAGE_ADDRESSES') }}</a
              >
            </div>
            <p v-if="customer?.document" class="text-xs text-n-slate-10">
              {{
                customer?.person_type === 'pj'
                  ? t('CONVERSATION_SIDEBAR.NERK.COMPANY_DOCUMENT')
                  : t('CONVERSATION_SIDEBAR.NERK.PERSON_DOCUMENT')
              }}
              · {{ customer.document }}
            </p>
          </div>
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
          :href="registrationUrl"
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

      <section
        v-if="flowStep === 'carts'"
        class="min-h-0 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 p-5"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h3 class="text-base font-medium text-n-slate-12">
              {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_CARTS_TITLE') }}
            </h3>
            <p class="mt-1 max-w-2xl text-sm text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_CARTS_DESCRIPTION') }}
            </p>
          </div>
          <Button
            :label="t('CONVERSATION_SIDEBAR.NERK.CREATE_NEW_CART')"
            color="blue"
            size="sm"
            :is-loading="saving"
            @click="startNewCart"
          />
        </div>
        <div v-if="loadingCarts" class="flex justify-center py-12">
          <Spinner size="24" class="text-n-brand" />
        </div>
        <div v-else-if="carts.length" class="mt-5 grid gap-3 md:grid-cols-2">
          <button
            v-for="cart in carts"
            :key="cart.id"
            type="button"
            class="group rounded-xl border border-n-weak p-4 text-left transition hover:border-n-brand hover:bg-n-brand/5"
            @click="selectCart(cart)"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ t('CONVERSATION_SIDEBAR.NERK.CART_IN_PROGRESS') }}
                </p>
                <p class="mt-1 text-xs text-n-slate-11">
                  {{
                    t('CONVERSATION_SIDEBAR.NERK.CART_ITEMS_COUNT', {
                      count: cart.quote?.lines?.length || 0,
                    })
                  }}
                </p>
              </div>
              <span class="text-sm font-semibold text-n-slate-12">
                {{ formatCurrency(cart.quote?.amounts?.estimated_total_cents) }}
              </span>
            </div>
            <div
              class="mt-4 flex items-center justify-between border-t border-n-weak pt-3"
            >
              <span class="font-mono text-[11px] text-n-slate-10">
                {{ cart.id.slice(0, 8) }}
              </span>
              <span class="text-xs font-medium text-n-brand">
                {{ t('CONVERSATION_SIDEBAR.NERK.CONTINUE_CART') }}
              </span>
            </div>
          </button>
        </div>
        <div v-else class="py-12 text-center">
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION_SIDEBAR.NERK.NO_OPEN_CART') }}
          </p>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.NERK.NO_OPEN_CART_DESCRIPTION') }}
          </p>
        </div>
      </section>

      <div
        v-else
        class="grid min-h-0 flex-1 gap-4 overflow-hidden lg:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <section class="flex min-h-0 flex-col gap-3 overflow-hidden">
          <div class="flex items-center gap-2 overflow-x-auto pb-1">
            <button
              type="button"
              class="shrink-0 rounded-lg border border-n-weak px-3 py-2 text-xs font-medium text-n-slate-12"
              @click="flowStep = 'carts'"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.BACK_TO_CARTS') }}
            </button>
            <button
              type="button"
              class="shrink-0 rounded-lg border border-n-weak px-3 py-2 text-xs font-medium text-n-slate-12"
              :disabled="saving"
              @click="startNewCart"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.NEW_CART') }}
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

          <div v-if="promotions.length" class="space-y-2">
            <p
              class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.AVAILABLE_COUPONS') }}
            </p>
            <div class="flex gap-2 overflow-x-auto pb-1">
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
          </div>

          <div v-if="combos.length" class="shrink-0 space-y-2">
            <p
              class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.AVAILABLE_COMBOS') }}
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <button
                v-for="combo in combos"
                :key="combo.id"
                type="button"
                class="flex items-center gap-3 rounded-xl border border-n-teal-7 bg-n-teal-2 p-2.5 text-left text-xs transition hover:border-n-teal-9"
                :disabled="saving"
                @click="addCombo(combo)"
              >
                <span class="flex -space-x-3">
                  <img
                    v-for="(image, index) in comboImages(combo)"
                    :key="`${combo.id}-${index}`"
                    :src="image"
                    :alt="combo.name"
                    class="size-11 rounded-lg border-2 border-n-teal-2 object-cover"
                  />
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate font-medium text-n-teal-12">{{
                    combo.name
                  }}</span>
                  <span class="line-clamp-2 text-n-teal-11">{{
                    combo.description ||
                    t('CONVERSATION_SIDEBAR.NERK.ADD_COMBO')
                  }}</span>
                </span>
                <span class="font-medium text-n-teal-12">{{
                  t('CONVERSATION_SIDEBAR.NERK.INCREASE_SYMBOL')
                }}</span>
              </button>
            </div>
          </div>

          <div
            class="grid min-h-0 flex-1 auto-rows-max grid-cols-1 gap-3 overflow-y-auto pr-1 2xl:grid-cols-2"
          >
            <article
              v-for="product in products"
              :key="product.id"
              class="rounded-xl border border-n-weak bg-n-solid-1 p-3 transition hover:border-n-brand"
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
              <div v-if="selectedVariant(product)" class="mt-3 space-y-2">
                <label class="block text-[11px] font-medium text-n-slate-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.SELECT_VARIANT') }}
                </label>
                <select
                  v-model="selectedVariantIds[product.id]"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
                >
                  <option
                    v-for="variant in availableVariants(product)"
                    :key="variant.id"
                    :value="variant.id"
                  >
                    {{ variantOptionLabel(variant) }}
                  </option>
                </select>
                <div
                  class="flex items-center gap-3 rounded-lg bg-n-alpha-2 p-2"
                >
                  <img
                    :src="variantImage(product, selectedVariant(product))"
                    :alt="selectedVariant(product).name"
                    class="size-12 rounded-md object-cover"
                  />
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-xs font-medium text-n-slate-12">
                      {{ variantAttributes(selectedVariant(product)) }}
                    </p>
                    <span class="block text-[11px] text-n-slate-11">
                      {{
                        t('CONVERSATION_SIDEBAR.NERK.VARIANT_STOCK', {
                          sku: selectedVariant(product).sku,
                          count: selectedVariant(product).stock,
                        })
                      }}
                    </span>
                    <span
                      v-if="selectedVariant(product).promotion"
                      class="block text-[11px] text-n-teal-11"
                    >
                      {{ selectedVariant(product).promotion.name }}
                    </span>
                  </div>
                  <div class="text-right text-xs">
                    <p class="font-semibold text-n-slate-12">
                      {{
                        formatCurrency(
                          selectedVariant(product).offer_price_cents
                        )
                      }}
                    </p>
                    <p v-if="clubEligible" class="text-n-teal-11">
                      {{
                        formatCurrency(
                          selectedVariant(product).club_price_cents
                        )
                      }}
                    </p>
                  </div>
                </div>
                <Button
                  :label="t('CONVERSATION_SIDEBAR.NERK.ADD_TO_CART')"
                  color="blue"
                  size="sm"
                  type="button"
                  class="w-full"
                  :disabled="saving"
                  @click="addSelectedVariant(product)"
                />
              </div>
              <p v-else class="mt-3 text-xs text-n-ruby-11">
                {{ t('CONVERSATION_SIDEBAR.NERK.NO_VARIANTS_AVAILABLE') }}
              </p>
            </article>
            <p
              v-if="!searching && !products.length"
              class="col-span-full rounded-xl border border-dashed border-n-weak p-10 text-center text-sm text-n-slate-11"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.NO_PRODUCTS_FOUND') }}
            </p>
          </div>
        </section>

        <aside
          class="flex min-h-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
        >
          <div class="border-b border-n-weak p-4">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION_SIDEBAR.NERK.CART_TITLE') }}
              </h4>
              <Spinner v-if="saving" size="18" class="text-n-brand" />
            </div>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ cartSyncLabel }}
            </p>
            <div
              class="mt-3 grid grid-cols-2 gap-1 rounded-lg bg-n-alpha-2 p-1"
            >
              <button
                type="button"
                class="rounded-md px-2 py-1.5 text-[11px] font-medium"
                :class="
                  cartPricingMode === 'official'
                    ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                    : 'text-n-slate-11'
                "
                :disabled="saving"
                @click="setCartPricingMode('official')"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.REGULAR_PRICE') }}
              </button>
              <button
                type="button"
                class="rounded-md px-2 py-1.5 text-[11px] font-medium"
                :class="
                  cartPricingMode === 'club'
                    ? 'bg-n-teal-3 text-n-teal-11 shadow-sm'
                    : 'text-n-slate-11'
                "
                :disabled="!clubEligible || saving"
                @click="setCartPricingMode('club')"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_PRICE') }}
              </button>
            </div>
          </div>

          <div class="min-h-0 flex-1 divide-y divide-n-weak overflow-y-auto">
            <div
              v-for="line in lines"
              :key="line.variantId || line.variant_id"
              class="p-3"
              :class="
                lineCombo(line)
                  ? 'border-l-2 border-n-teal-8 bg-n-teal-2/40'
                  : ''
              "
            >
              <p
                v-if="lineCombo(line)"
                class="mb-2 text-[10px] font-medium uppercase tracking-wide text-n-teal-11"
              >
                {{ lineCombo(line).name }}
              </p>
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
            <div v-if="cartUrl" class="mt-3 grid grid-cols-3 gap-1.5">
              <button
                type="button"
                class="rounded-lg border border-n-weak px-2 py-2 text-[11px] font-medium text-n-slate-12"
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
                class="rounded-lg bg-n-brand px-2 py-2 text-[11px] font-medium text-white"
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
                class="rounded-lg border border-n-weak px-2 py-2 text-center text-[11px] font-medium text-n-slate-12"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_BACKOFFICE') }}
              </a>
            </div>
          </div>
        </aside>
      </div>
    </div>
    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <p class="text-xs text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.NERK.EXPLICIT_CLOSE_HELP') }}
        </p>
        <Button
          color="slate"
          variant="faded"
          :disabled="saving"
          :label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
          @click="dialog?.close()"
        />
      </div>
    </template>
  </Dialog>
</template>
