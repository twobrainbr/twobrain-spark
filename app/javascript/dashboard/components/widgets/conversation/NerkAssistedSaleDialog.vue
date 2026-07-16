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
const nerkLogoUrl = `${[
  '/dashboard',
  'images',
  'integrations',
  'nerk.svg',
].join('/')}?v=official-20260716`;
const flowStep = ref('carts');
const query = ref('');
const catalogMode = ref('all');
const categoryFilter = ref('all');
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
const shippingZip = ref('');
const shippingServiceId = ref('');
const shippingDiscountCents = ref(0);
const emailValidation = ref(null);
const validatingEmail = ref(false);
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
let saveTimer;
let saveRevision = 0;

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
const categories = computed(() => {
  const rows = products.value
    .map(product => product.category)
    .filter(category => category?.slug && category?.name);
  return [...new Map(rows.map(category => [category.slug, category])).values()];
});
const visibleProducts = computed(() => {
  if (catalogMode.value === 'combos') return [];
  if (categoryFilter.value === 'all') return products.value;
  return products.value.filter(
    product => product.category?.slug === categoryFilter.value
  );
});
const visibleCombos = computed(() =>
  catalogMode.value === 'products' ? [] : combos.value
);
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

const productImage = product =>
  product.images?.find(image => image.is_primary || image.isPrimary)?.url ||
  product.images?.[0]?.url ||
  product.variants?.flatMap(variant => variant.images || [])?.[0]?.url ||
  '';
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
  shippingZip.value = cart.quote?.shipping?.zip || '';
  shippingServiceId.value = cart.quote?.shipping?.selected?.serviceId || '';
  shippingDiscountCents.value =
    cart.quote?.amounts?.shipping_discount_cents || 0;
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
  saveRevision += 1;
  const revision = saveRevision;
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
      currentCartId.value,
      {
        zip: shippingZip.value,
        serviceId: shippingServiceId.value,
        discountCents: Number(shippingDiscountCents.value || 0),
      }
    );
    if (revision !== saveRevision) return;
    applyCart(response.data.assisted_order);
    carts.value = [
      response.data.assisted_order,
      ...carts.value.filter(
        cart => cart.id !== response.data.assisted_order.id
      ),
    ];
    emit('saved');
    emit('cartsUpdated');
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_SAVE_ERROR');
  } finally {
    if (revision === saveRevision) saving.value = false;
  }
};

const scheduleCartSave = () => {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(saveCart, 180);
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
  scheduleCartSave();
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
  scheduleCartSave();
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
  scheduleCartSave();
};

const removeLine = async line => {
  lines.value = lines.value.filter(candidate => candidate !== line);
  scheduleCartSave();
};

const setCartPricingMode = async mode => {
  if (mode === 'club' && !clubEligible.value) return;
  cartPricingMode.value = mode;
  lines.value.forEach(line => {
    line.pricingMode = mode;
    line.pricing_mode = mode;
  });
  if (lines.value.length) scheduleCartSave();
};

const resetCart = () => {
  currentCartId.value = null;
  lines.value = [];
  quote.value = null;
  cartUrl.value = '';
  paymentUrl.value = '';
  backofficeUrl.value = '';
  couponCode.value = '';
  shippingZip.value = '';
  shippingServiceId.value = '';
  shippingDiscountCents.value = 0;
  query.value = '';
  products.value = [];
  lastSavedAt.value = null;
  error.value = '';
};

const selectCart = async cart => {
  applyCart(cart);
  flowStep.value = 'pdv';
  await Promise.all([
    promotions.value.length ? Promise.resolve() : loadPromotions(),
    products.value.length
      ? Promise.resolve()
      : searchProducts(query.value.trim()),
  ]);
};

const startNewCart = async () => {
  saving.value = true;
  error.value = '';
  try {
    const response = await NerkAPI.startNewCart(props.contactId);
    applyCart(response.data.cart);
    carts.value = [response.data.cart];
    flowStep.value = 'pdv';
    await Promise.all([loadPromotions(), searchProducts(query.value.trim())]);
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
  const tasks = [loadCarts(), loadPromotions(), searchProducts('')];
  if (props.customer?.email) {
    validatingEmail.value = true;
    tasks.push(
      NerkAPI.validateCustomerField('email', props.customer.email)
        .then(response => {
          emailValidation.value = response.data.validation;
        })
        .catch(() => {
          emailValidation.value = null;
        })
        .finally(() => {
          validatingEmail.value = false;
        })
    );
  }
  await Promise.all(tasks);
  const cart = carts.value.find(candidate => candidate.id === cartId);
  if (cart) await selectCart(cart);
};

const closePanel = () => {
  window.clearTimeout(saveTimer);
  if (lines.value.length) saveCart();
  dialog.value?.close();
};

onBeforeUnmount(() => {
  window.clearTimeout(searchTimer);
  window.clearTimeout(saveTimer);
});
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="panel"
    position="right"
    title=""
    :show-cancel-button="false"
    :show-confirm-button="false"
    prevent-close
  >
    <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-hidden">
      <div
        class="relative flex shrink-0 items-center gap-3 border-b border-n-weak bg-n-solid-1 px-1 pb-3"
      >
        <img
          :src="nerkLogoUrl"
          :alt="t('CONVERSATION_SIDEBAR.NERK.BRAND_LOGO')"
          class="h-9 w-auto"
        />
        <div class="hidden min-w-0 sm:block">
          <p
            class="nerk-display truncate text-base font-semibold leading-none text-n-slate-12"
          >
            {{ t('CONVERSATION_SIDEBAR.NERK.ASSISTED_SALE_TITLE') }}
          </p>
          <p
            class="mt-1 text-[10px] uppercase tracking-[0.16em] text-n-slate-10"
          >
            {{ cartSyncLabel }}
          </p>
        </div>
        <span class="hidden h-8 w-px bg-n-weak lg:block" />
        <div class="flex min-w-0 flex-1 items-center gap-2 overflow-x-auto">
          <button
            type="button"
            class="flex shrink-0 items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-left hover:bg-n-alpha-2"
            @click="profileOpen = true"
          >
            <span class="i-lucide-wallet size-4 text-n-slate-12" />
            <span>
              <span class="block text-[10px] text-n-slate-10">{{
                t('CONVERSATION_SIDEBAR.NERK.WALLET_BALANCE')
              }}</span>
              <span
                class="nerk-display block text-sm font-semibold text-n-slate-12"
                >{{ formatCurrency(walletBalance) }}</span
              >
            </span>
          </button>
          <button
            type="button"
            class="flex shrink-0 items-center gap-2 rounded-lg border border-n-slate-12 bg-n-slate-12 px-3 py-1.5 text-left text-white hover:opacity-90"
            @click="profileOpen = true"
          >
            <span class="i-lucide-sparkles size-4 text-white" />
            <span>
              <span class="block text-[10px] text-white/70">{{
                t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS')
              }}</span>
              <span class="nerk-display block text-sm font-semibold text-white">
                {{ pointsBalance }} · {{ formatCurrency(redeemableValue) }}
              </span>
            </span>
          </button>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <button
            type="button"
            class="flex size-9 items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2"
            :aria-label="t('CONVERSATION_SIDEBAR.NERK.BACK_TO_CARTS')"
            @click="flowStep = 'carts'"
          >
            <span class="i-lucide-shopping-bag size-4" />
          </button>
          <button
            type="button"
            class="flex size-9 items-center justify-center rounded-lg bg-n-slate-12 text-white hover:opacity-90"
            :aria-label="t('CONVERSATION_SIDEBAR.NERK.NEW_CART')"
            :disabled="saving"
            @click="startNewCart"
          >
            <span class="i-lucide-plus size-4" />
          </button>
          <button
            type="button"
            class="flex items-center gap-2 rounded-lg p-1 pr-2 text-left hover:bg-n-alpha-2"
            @click="profileOpen = !profileOpen"
          >
            <span
              class="nerk-display flex size-8 items-center justify-center rounded-full bg-n-slate-12 text-xs font-semibold text-white"
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
            class="flex size-9 items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2"
            :aria-label="t('CONVERSATION_SIDEBAR.NERK.CLOSE_PDV')"
            @click="closePanel"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <div
          v-if="profileOpen"
          class="absolute right-3 top-[calc(100%+0.5rem)] z-30 flex max-h-[calc(100vh-8rem)] w-[min(24rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-xl"
        >
          <div class="flex items-start gap-3 border-b border-n-weak p-4">
            <span
              class="nerk-display flex size-11 shrink-0 items-center justify-center rounded-full bg-n-slate-12 text-sm font-semibold text-white"
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
              <span
                v-if="customer?.email"
                class="mt-1 inline-flex items-center gap-1 text-[10px]"
                :class="
                  emailValidation?.valid ? 'text-n-slate-12' : 'text-n-ruby-11'
                "
              >
                <span
                  :class="
                    validatingEmail
                      ? 'i-lucide-loader-circle animate-spin'
                      : emailValidation?.valid
                        ? 'i-lucide-badge-check'
                        : 'i-lucide-circle-alert'
                  "
                  class="size-3"
                />
                {{
                  validatingEmail
                    ? t('CONVERSATION_SIDEBAR.NERK.VALIDATING_EMAIL')
                    : emailValidation?.valid
                      ? t('CONVERSATION_SIDEBAR.NERK.EMAIL_VALID')
                      : t('CONVERSATION_SIDEBAR.NERK.EMAIL_REVIEW')
                }}
              </span>
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
              <div class="rounded-lg border border-n-weak bg-n-solid-1 p-3">
                <p class="text-[10px] uppercase tracking-wide text-n-slate-10">
                  {{ t('CONVERSATION_SIDEBAR.NERK.WALLET_BALANCE') }}
                </p>
                <p
                  class="nerk-display mt-1 text-lg font-semibold text-n-slate-12"
                >
                  {{ formatCurrency(walletBalance) }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ t('CONVERSATION_SIDEBAR.NERK.WALLET_CHECKOUT_HELP') }}
                </p>
              </div>
              <div class="rounded-lg bg-n-slate-12 p-3 text-white">
                <p class="text-[10px] uppercase tracking-wide text-white/65">
                  {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_POINTS') }}
                </p>
                <p class="nerk-display mt-1 text-lg font-semibold text-white">
                  {{ pointsBalance }}
                </p>
                <p class="text-[11px] text-white/70">
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
        class="flex shrink-0 flex-wrap items-center justify-between gap-3 rounded-lg border border-n-slate-12 bg-n-solid-1 p-3 text-xs text-n-slate-12"
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
          class="rounded-lg bg-n-slate-12 px-3 py-2 font-medium text-white"
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
            <h3 class="nerk-display text-xl font-semibold text-n-slate-12">
              {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_CARTS_TITLE') }}
            </h3>
            <p class="mt-1 max-w-2xl text-sm text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.NERK.OPEN_CARTS_DESCRIPTION') }}
            </p>
          </div>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-slate-12 px-4 py-2 text-xs font-medium text-white"
            :disabled="saving"
            @click="startNewCart"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('CONVERSATION_SIDEBAR.NERK.CREATE_NEW_CART') }}
          </button>
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
              <span
                class="nerk-display text-base font-semibold text-n-slate-12"
              >
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
        class="grid min-h-0 flex-1 gap-4 overflow-hidden md:grid-cols-[minmax(0,1fr)_20rem] xl:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <section class="flex min-h-0 flex-col gap-3 overflow-hidden">
          <div class="relative shrink-0">
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

          <div class="flex shrink-0 items-center gap-2 overflow-x-auto pb-1">
            <button
              v-for="mode in ['all', 'products', 'combos']"
              :key="mode"
              type="button"
              class="shrink-0 rounded-full border px-3 py-1.5 text-xs font-medium"
              :class="
                catalogMode === mode
                  ? 'border-n-slate-12 bg-n-slate-12 text-white'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-11'
              "
              @click="catalogMode = mode"
            >
              {{
                mode === 'all'
                  ? t('CONVERSATION_SIDEBAR.NERK.FILTER_ALL')
                  : mode === 'products'
                    ? t('CONVERSATION_SIDEBAR.NERK.FILTER_PRODUCTS')
                    : t('CONVERSATION_SIDEBAR.NERK.FILTER_COMBOS')
              }}
            </button>
            <span class="h-5 w-px shrink-0 bg-n-weak" />
            <button
              type="button"
              class="shrink-0 rounded-full border px-3 py-1.5 text-xs font-medium"
              :class="
                categoryFilter === 'all'
                  ? 'border-n-slate-12 bg-n-slate-12 text-white'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-11'
              "
              @click="categoryFilter = 'all'"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.ALL_CATEGORIES') }}
            </button>
            <button
              v-for="category in categories"
              :key="category.slug"
              type="button"
              class="shrink-0 rounded-full border px-3 py-1.5 text-xs font-medium"
              :class="
                categoryFilter === category.slug
                  ? 'border-n-slate-12 bg-n-slate-12 text-white'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-11'
              "
              @click="categoryFilter = category.slug"
            >
              {{ category.name }}
            </button>
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
                  scheduleCartSave();
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

          <div
            class="grid min-h-0 flex-1 auto-rows-max grid-cols-1 gap-3 overflow-y-auto overscroll-contain pr-2 lg:grid-cols-2"
          >
            <article
              v-for="combo in visibleCombos"
              :key="`combo-${combo.id}`"
              class="rounded-xl border-2 border-n-slate-12 bg-n-solid-1 p-3"
            >
              <div class="flex items-start gap-3">
                <span
                  class="grid size-20 shrink-0 grid-cols-2 gap-0.5 overflow-hidden rounded-lg bg-n-alpha-2 p-0.5"
                >
                  <img
                    v-for="(image, index) in comboImages(combo)"
                    :key="`${combo.id}-${index}`"
                    :src="image"
                    :alt="combo.name"
                    class="size-full min-h-0 min-w-0 object-cover"
                    :class="index === 0 ? 'row-span-2' : ''"
                  />
                  <span
                    v-if="!comboImages(combo).length"
                    class="i-lucide-package-open col-span-2 m-auto size-7 text-n-slate-10"
                  />
                </span>
                <div class="min-w-0 flex-1">
                  <span
                    class="inline-flex rounded-full bg-n-slate-12 px-2 py-0.5 text-[9px] font-semibold uppercase tracking-wider text-white"
                  >
                    {{ t('CONVERSATION_SIDEBAR.NERK.FILTER_COMBOS') }}
                  </span>
                  <h4
                    class="nerk-display mt-2 line-clamp-2 text-base font-semibold leading-tight text-n-slate-12"
                  >
                    {{ combo.name }}
                  </h4>
                  <p class="mt-1 line-clamp-2 text-xs text-n-slate-10">
                    {{ combo.description }}
                  </p>
                </div>
              </div>
              <button
                type="button"
                class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg bg-n-slate-12 px-3 py-2 text-xs font-medium text-white"
                :disabled="saving"
                @click="addCombo(combo)"
              >
                <span class="i-lucide-plus size-4" />
                {{ t('CONVERSATION_SIDEBAR.NERK.ADD_COMBO') }}
              </button>
            </article>
            <article
              v-for="product in visibleProducts"
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
                  <p
                    class="nerk-display line-clamp-2 text-base font-semibold leading-tight text-n-slate-12"
                  >
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
                    <p
                      class="nerk-display text-sm font-semibold text-n-slate-12"
                    >
                      {{
                        formatCurrency(
                          selectedVariant(product).offer_price_cents
                        )
                      }}
                    </p>
                    <p v-if="clubEligible" class="nerk-display text-n-slate-10">
                      {{
                        formatCurrency(
                          selectedVariant(product).club_price_cents
                        )
                      }}
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  class="flex w-full items-center justify-center gap-2 rounded-lg bg-n-slate-12 px-3 py-2 text-xs font-medium text-white"
                  :disabled="saving"
                  @click="addSelectedVariant(product)"
                >
                  <span class="i-lucide-plus size-4" />
                  {{ t('CONVERSATION_SIDEBAR.NERK.ADD_TO_CART') }}
                </button>
              </div>
              <p v-else class="mt-3 text-xs text-n-ruby-11">
                {{ t('CONVERSATION_SIDEBAR.NERK.NO_VARIANTS_AVAILABLE') }}
              </p>
            </article>
            <p
              v-if="
                !searching && !visibleProducts.length && !visibleCombos.length
              "
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
              <h4 class="nerk-display text-lg font-semibold text-n-slate-12">
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
                    ? 'bg-n-slate-12 text-white shadow-sm'
                    : 'text-n-slate-11'
                "
                :disabled="!clubEligible || saving"
                @click="setCartPricingMode('club')"
              >
                {{ t('CONVERSATION_SIDEBAR.NERK.CLUB_PRICE') }}
              </button>
            </div>
          </div>

          <div
            class="min-h-0 flex-1 divide-y divide-n-weak overflow-y-auto overscroll-contain"
          >
            <div
              v-for="line in lines"
              :key="line.variantId || line.variant_id"
              class="p-3"
              :class="
                lineCombo(line)
                  ? 'border-l-2 border-n-slate-12 bg-n-alpha-2'
                  : ''
              "
            >
              <p
                v-if="lineCombo(line)"
                class="mb-2 text-[10px] font-medium uppercase tracking-wide text-n-slate-12"
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
                <span
                  class="nerk-display text-sm font-semibold text-n-slate-12"
                  >{{
                    formatCurrency(
                      (line.unitPriceCents || line.unit_price_cents) *
                        line.quantity
                    )
                  }}</span
                >
              </div>
            </div>
            <p
              v-if="!lines.length"
              class="p-8 text-center text-sm text-n-slate-11"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.EMPTY_CART') }}
            </p>
          </div>

          <div
            class="max-h-[52%] shrink-0 overflow-y-auto overscroll-contain border-t border-n-weak p-4"
          >
            <div class="mb-3 rounded-lg border border-n-weak bg-n-alpha-2 p-3">
              <div class="flex items-center gap-2">
                <span class="i-lucide-truck size-4 text-n-slate-12" />
                <p class="nerk-display text-sm font-semibold text-n-slate-12">
                  {{ t('CONVERSATION_SIDEBAR.NERK.SHIPPING_CONFIGURATION') }}
                </p>
              </div>
              <div class="mt-2 grid grid-cols-2 gap-2">
                <label
                  class="text-[10px] uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('CONVERSATION_SIDEBAR.NERK.POSTAL_CODE') }}
                  <input
                    v-model="shippingZip"
                    inputmode="numeric"
                    maxlength="9"
                    class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-xs"
                    :placeholder="
                      t('CONVERSATION_SIDEBAR.NERK.POSTAL_CODE_PLACEHOLDER')
                    "
                    @change="scheduleCartSave"
                  />
                </label>
                <label
                  class="text-[10px] uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('CONVERSATION_SIDEBAR.NERK.SHIPPING_DISCOUNT') }}
                  <input
                    :value="(shippingDiscountCents / 100).toFixed(2)"
                    type="number"
                    min="0"
                    step="0.01"
                    class="nerk-display mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-xs"
                    @change="
                      shippingDiscountCents = Math.round(
                        Number($event.target.value || 0) * 100
                      );
                      scheduleCartSave();
                    "
                  />
                </label>
              </div>
              <select
                v-if="quote?.shipping?.options?.length"
                v-model="shippingServiceId"
                class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-xs"
                @change="scheduleCartSave"
              >
                <option
                  v-for="option in quote.shipping.options"
                  :key="option.serviceId"
                  :value="option.serviceId"
                >
                  {{ option.carrier }} · {{ option.service }} ·
                  {{ formatCurrency(option.customerPriceCents) }}
                </option>
              </select>
              <p
                v-else-if="quote?.shipping?.fallback_reason"
                class="mt-2 text-[10px] text-n-slate-10"
              >
                {{ quote.shipping.fallback_reason }}
              </p>
            </div>
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
                <dd class="nerk-display">
                  {{ formatCurrency(amounts.subtotal_cents) }}
                </dd>
              </div>
              <div
                v-if="amounts.discount_cents"
                class="flex justify-between text-n-slate-12"
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
              <div
                v-if="amounts.shipping_discount_cents"
                class="flex justify-between text-n-slate-12"
              >
                <dt>{{ t('CONVERSATION_SIDEBAR.NERK.SHIPPING_DISCOUNT') }}</dt>
                <dd class="nerk-display">
                  - {{ formatCurrency(amounts.shipping_discount_cents) }}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-n-slate-11">
                  {{ t('CONVERSATION_SIDEBAR.NERK.ESTIMATED_SHIPPING') }}
                </dt>
                <dd class="nerk-display">
                  {{ formatCurrency(amounts.estimated_shipping_cents) }}
                </dd>
              </div>
              <div
                class="flex justify-between border-t border-n-weak pt-2 text-sm font-medium"
              >
                <dt>{{ t('CONVERSATION_SIDEBAR.NERK.ESTIMATED_TOTAL') }}</dt>
                <dd class="nerk-display text-base font-semibold">
                  {{ formatCurrency(amounts.estimated_total_cents) }}
                </dd>
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
                class="rounded-lg bg-n-slate-12 px-2 py-2 text-[11px] font-medium text-white"
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
  </Dialog>
</template>
