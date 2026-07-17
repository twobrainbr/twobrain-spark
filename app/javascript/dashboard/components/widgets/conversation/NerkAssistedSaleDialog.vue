<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import NerkAPI from 'dashboard/api/integrations/nerk';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
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
const coupons = ref([]);
const combos = ref([]);
const lines = ref([]);
const currentCartId = ref(null);
const quote = ref(null);
const cartUrl = ref('');
const paymentUrl = ref('');
const backofficeUrl = ref('');
const couponCode = ref('');
const selectedAddressId = ref('');
const shippingZip = ref('');
const shippingServiceId = ref('');
const shippingDiscountCents = ref(0);
const shippingDiscountInput = ref('');
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
const previewLine = ref(null);
const addressPickerOpen = ref(false);
const addressSearch = ref('');
const redeemPoints = ref(0);
const redeeming = ref(false);
const redeemedPointsBalance = ref(null);
const redeemedWalletBalance = ref(null);
let searchTimer;
let saveTimer;
let saveInFlight = false;
let saveQueued = false;

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
const customerAddresses = computed(() =>
  [...(props.customer?.addresses || [])].sort(
    (first, second) =>
      Number(second.isDefault || second.is_default) -
        Number(first.isDefault || first.is_default) ||
      new Date(second.updatedAt || second.updated_at || 0).getTime() -
        new Date(first.updatedAt || first.updated_at || 0).getTime()
  )
);
const selectedAddress = computed(() =>
  customerAddresses.value.find(
    address => address.id === selectedAddressId.value
  )
);
const shippingDiscountLimitCents = computed(
  () => amounts.value.shipping_before_discount_cents || 0
);
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
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format((amount || 0) / 100);
const formatPostalCode = zip =>
  String(zip || '')
    .replace(/\D/g, '')
    .replace(/^(\d{5})(\d{3})$/, '$1-$2');
const addressLabel = address =>
  [
    address.recipient,
    `${address.street}, ${address.number}`,
    address.complement,
    `${address.city}/${address.state}`,
    formatPostalCode(address.zip),
  ]
    .filter(Boolean)
    .join(' · ');
const couponBenefit = coupon =>
  coupon.discount_type === 'percent'
    ? t('CONVERSATION_SIDEBAR.NERK.COUPON_PERCENT', {
        value: coupon.value,
      })
    : t('CONVERSATION_SIDEBAR.NERK.COUPON_FIXED', {
        value: formatCurrency(coupon.value),
      });
const couponLabel = coupon => `${coupon.code} · ${couponBenefit(coupon)}`;

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
const lineDetail = line =>
  [lineVariantAttributes(line), line.sku].filter(Boolean).join(' · ');
const shippingOptionLabel = option =>
  [option.carrier, option.service, formatCurrency(option.customerPriceCents)]
    .filter(Boolean)
    .join(' · ');
const parseCurrencyInput = value => {
  const normalized = String(value || '')
    .replace(/[^\d,.-]/g, '')
    .replace(/\./g, '')
    .replace(',', '.');
  const amount = Number(normalized);
  return Number.isFinite(amount) ? Math.max(0, Math.round(amount * 100)) : 0;
};
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
const variantOptions = product =>
  availableVariants(product).map(variant => ({
    value: variant.id,
    label: variantOptionLabel(variant),
  }));
const filteredAddresses = computed(() => {
  const search = addressSearch.value.trim().toLocaleLowerCase('pt-BR');
  if (!search) return customerAddresses.value;
  return customerAddresses.value.filter(address =>
    addressLabel(address).toLocaleLowerCase('pt-BR').includes(search)
  );
});
const couponOptions = computed(() => [
  { value: '', label: t('CONVERSATION_SIDEBAR.NERK.NO_COUPON') },
  ...coupons.value.map(coupon => ({
    value: coupon.code,
    label: couponLabel(coupon),
  })),
]);
const shippingOptions = computed(() =>
  (quote.value?.shipping?.options || []).map(option => ({
    value: option.serviceId,
    label: shippingOptionLabel(option),
  }))
);

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
  const quotedAddressId = cart.quote?.shipping?.address_id;
  const quotedZip = cart.quote?.shipping?.zip?.replace(/\D/g, '');
  const resolvedAddress =
    customerAddresses.value.find(address => address.id === quotedAddressId) ||
    customerAddresses.value.find(
      address => address.zip?.replace(/\D/g, '') === quotedZip
    ) ||
    customerAddresses.value[0];
  selectedAddressId.value = resolvedAddress?.id || '';
  shippingZip.value = resolvedAddress?.zip || cart.quote?.shipping?.zip || '';
  shippingServiceId.value = cart.quote?.shipping?.selected?.serviceId || '';
  shippingDiscountCents.value =
    cart.quote?.amounts?.shipping_discount_cents || 0;
  shippingDiscountInput.value = formatCurrency(shippingDiscountCents.value);
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
    coupons.value = response.data.coupons || [];
    combos.value = response.data.combos || [];
  } catch {
    coupons.value = [];
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

const persistQueuedCart = async () => {
  if (!saveQueued) return;
  saveQueued = false;
  const snapshot = lines.value.map(line => ({
    variant_id: line.variantId || line.variant_id,
    quantity: line.quantity,
    pricing_mode: line.pricingMode || line.pricing_mode || 'official',
  }));
  const snapshotState = {
    lines: snapshot,
    couponCode: couponCode.value,
    addressId: selectedAddressId.value,
    serviceId: shippingServiceId.value,
    shippingDiscountCents: Number(shippingDiscountCents.value || 0),
  };
  const snapshotSignature = JSON.stringify(snapshotState);
  try {
    const response = await NerkAPI.createAssistedOrder(
      props.contactId,
      snapshot,
      couponCode.value,
      currentCartId.value,
      {
        addressId: selectedAddressId.value,
        zip: shippingZip.value,
        serviceId: shippingServiceId.value,
        discountCents: Number(shippingDiscountCents.value || 0),
      }
    );
    const currentSignature = JSON.stringify({
      lines: lines.value.map(line => ({
        variant_id: line.variantId || line.variant_id,
        quantity: line.quantity,
        pricing_mode: line.pricingMode || line.pricing_mode || 'official',
      })),
      couponCode: couponCode.value,
      addressId: selectedAddressId.value,
      serviceId: shippingServiceId.value,
      shippingDiscountCents: Number(shippingDiscountCents.value || 0),
    });
    if (!saveQueued && snapshotSignature === currentSignature) {
      applyCart(response.data.assisted_order);
      carts.value = [
        response.data.assisted_order,
        ...carts.value.filter(
          cart => cart.id !== response.data.assisted_order.id
        ),
      ];
      emit('saved');
      emit('cartsUpdated');
    }
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      t('CONVERSATION_SIDEBAR.NERK.CART_SAVE_ERROR');
  }
  if (saveQueued) await persistQueuedCart();
};

const saveCart = async () => {
  if (!lines.value.length && !currentCartId.value) return;
  saveQueued = true;
  if (saveInFlight) return;

  saveInFlight = true;
  saving.value = true;
  error.value = '';
  try {
    await persistQueuedCart();
  } finally {
    saveInFlight = false;
    saving.value = false;
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

const chooseAddress = () => {
  shippingZip.value = selectedAddress.value?.zip || '';
  shippingServiceId.value = '';
  if (lines.value.length) scheduleCartSave();
};

const selectAddress = addressId => {
  if (!addressId) return;
  selectedAddressId.value = addressId;
  addressPickerOpen.value = false;
  chooseAddress();
};

const toggleAddressPicker = () => {
  addressPickerOpen.value = !addressPickerOpen.value;
  addressSearch.value = '';
};

const selectShippingService = serviceId => {
  if (!serviceId) return;
  shippingServiceId.value = serviceId;
  scheduleCartSave();
};

const selectCoupon = code => {
  couponCode.value = code;
  scheduleCartSave();
};

const selectVariant = (product, variantId) => {
  if (variantId) selectedVariantIds.value[product.id] = variantId;
};

const editShippingDiscount = event => {
  shippingDiscountInput.value = (
    shippingDiscountCents.value / 100
  ).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  window.setTimeout(() => event.target.select());
};

const commitShippingDiscount = event => {
  const requestedCents = parseCurrencyInput(event.target.value);
  shippingDiscountCents.value = Math.min(
    requestedCents,
    shippingDiscountLimitCents.value
  );
  shippingDiscountInput.value = formatCurrency(shippingDiscountCents.value);
  if (lines.value.length) scheduleCartSave();
};

const resetCart = () => {
  saveQueued = false;
  currentCartId.value = null;
  lines.value = [];
  quote.value = null;
  cartUrl.value = '';
  paymentUrl.value = '';
  backofficeUrl.value = '';
  couponCode.value = '';
  selectedAddressId.value = customerAddresses.value[0]?.id || '';
  shippingZip.value = customerAddresses.value[0]?.zip || '';
  shippingServiceId.value = '';
  shippingDiscountCents.value = 0;
  shippingDiscountInput.value = formatCurrency(0);
  query.value = '';
  products.value = [];
  lastSavedAt.value = null;
  error.value = '';
  previewLine.value = null;
  addressPickerOpen.value = false;
  addressSearch.value = '';
};

const selectCart = async cart => {
  applyCart(cart);
  flowStep.value = 'pdv';
  await Promise.all([
    coupons.value.length || combos.value.length
      ? Promise.resolve()
      : loadPromotions(),
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
  if (currentCartId.value) saveCart();
  dialog.value?.close();
};

watch(
  () =>
    customerAddresses.value
      .map(address =>
        [
          address.id,
          address.zip,
          address.street,
          address.number,
          address.updatedAt || address.updated_at,
        ].join(':')
      )
      .join('|'),
  () => {
    const currentAddress = selectedAddress.value;
    if (!currentAddress && customerAddresses.value.length) {
      selectedAddressId.value = customerAddresses.value[0].id;
      shippingZip.value = customerAddresses.value[0].zip || '';
      shippingServiceId.value = '';
      if (flowStep.value === 'pdv' && lines.value.length) scheduleCartSave();
      return;
    }

    if (
      currentAddress &&
      currentAddress.zip?.replace(/\D/g, '') !==
        shippingZip.value.replace(/\D/g, '')
    ) {
      shippingZip.value = currentAddress.zip || '';
      shippingServiceId.value = '';
      if (flowStep.value === 'pdv' && lines.value.length) scheduleCartSave();
    }
  }
);

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
                <ComboBox
                  :model-value="selectedVariantIds[product.id]"
                  :options="variantOptions(product)"
                  :placeholder="t('CONVERSATION_SIDEBAR.NERK.SELECT_VARIANT')"
                  :search-placeholder="
                    t('CONVERSATION_SIDEBAR.NERK.SEARCH_VARIANT')
                  "
                  :empty-state="
                    t('CONVERSATION_SIDEBAR.NERK.NO_VARIANTS_AVAILABLE')
                  "
                  :clearable="false"
                  active-color="slate"
                  class="[&_button]:!px-2 [&_button]:!py-1.5 [&_button]:!text-xs"
                  @update:model-value="selectVariant(product, $event)"
                />
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
          class="relative flex min-h-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
        >
          <div
            v-if="previewLine"
            class="absolute inset-3 z-20 flex flex-col items-center justify-center rounded-xl bg-n-slate-12/95 p-5 text-center text-white shadow-2xl"
          >
            <button
              type="button"
              class="absolute right-3 top-3 flex size-8 items-center justify-center rounded-full bg-white/15 hover:bg-white/25"
              :aria-label="t('CONVERSATION_SIDEBAR.NERK.CLOSE')"
              @click="previewLine = null"
            >
              <span class="i-lucide-x size-4" />
            </button>
            <img
              :src="previewLine.imageUrl || previewLine.image_url"
              :alt="previewLine.productName || previewLine.product_name"
              class="max-h-[58%] w-full rounded-lg object-contain"
            />
            <p class="nerk-display mt-4 text-lg font-semibold">
              {{ previewLine.productName || previewLine.product_name }}
            </p>
            <p class="mt-1 text-xs text-white/70">
              {{ lineDetail(previewLine) }}
            </p>
          </div>

          <div class="border-b border-n-weak p-3">
            <div class="flex items-center justify-between">
              <h4 class="nerk-display text-base font-semibold text-n-slate-12">
                {{ t('CONVERSATION_SIDEBAR.NERK.CART_TITLE') }}
              </h4>
              <Spinner v-if="saving" size="18" class="text-n-brand" />
            </div>
            <p class="mt-0.5 text-[10px] text-n-slate-10">
              {{ cartSyncLabel }}
            </p>
            <div
              v-if="quote"
              class="mt-2 flex items-end justify-between rounded-lg bg-n-slate-12 px-3 py-2 text-white"
            >
              <div>
                <p class="text-[9px] uppercase tracking-[0.14em] text-white/60">
                  {{ t('CONVERSATION_SIDEBAR.NERK.ESTIMATED_TOTAL') }}
                </p>
                <p class="nerk-display text-xl font-semibold leading-none">
                  {{ formatCurrency(amounts.estimated_total_cents) }}
                </p>
              </div>
              <p class="text-[10px] text-white/60">
                {{
                  t('CONVERSATION_SIDEBAR.NERK.CART_ITEMS_COUNT', {
                    count: lines.length,
                  })
                }}
              </p>
            </div>
            <div
              v-if="cartUrl || paymentUrl || backofficeUrl"
              class="mt-2 grid grid-cols-3 gap-1.5"
            >
              <button
                v-if="cartUrl"
                type="button"
                class="flex min-w-0 items-center justify-center gap-1 rounded-lg border border-n-weak px-2 py-1.5 text-[10px] font-medium text-n-slate-12 hover:bg-n-alpha-2"
                :aria-label="t('CONVERSATION_SIDEBAR.NERK.COPY_CART_LINK')"
                @click="copyLink('cart', cartUrl)"
              >
                <span class="i-lucide-link size-3.5 shrink-0" />
                <span class="truncate">
                  {{
                    copied === 'cart'
                      ? t('CONVERSATION_SIDEBAR.NERK.COPIED')
                      : t('CONVERSATION_SIDEBAR.NERK.CART_ACTION')
                  }}
                </span>
              </button>
              <button
                v-if="paymentUrl"
                type="button"
                class="flex min-w-0 items-center justify-center gap-1 rounded-lg bg-n-slate-12 px-2 py-1.5 text-[10px] font-medium text-white hover:opacity-90"
                :aria-label="t('CONVERSATION_SIDEBAR.NERK.COPY_PAYMENT_LINK')"
                @click="copyLink('payment', paymentUrl)"
              >
                <span class="i-lucide-credit-card size-3.5 shrink-0" />
                <span class="truncate">
                  {{
                    copied === 'payment'
                      ? t('CONVERSATION_SIDEBAR.NERK.COPIED')
                      : t('CONVERSATION_SIDEBAR.NERK.PAYMENT_ACTION')
                  }}
                </span>
              </button>
              <a
                v-if="backofficeUrl"
                :href="backofficeUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="flex min-w-0 items-center justify-center gap-1 rounded-lg border border-n-weak px-2 py-1.5 text-[10px] font-medium text-n-slate-12 hover:bg-n-alpha-2"
              >
                <span class="i-lucide-external-link size-3.5 shrink-0" />
                <span class="truncate">{{
                  t('CONVERSATION_SIDEBAR.NERK.BACKOFFICE_ACTION')
                }}</span>
              </a>
            </div>
            <div
              class="mt-2 grid grid-cols-2 gap-1 rounded-lg bg-n-alpha-2 p-1"
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
              class="px-3 py-2"
              :class="
                lineCombo(line)
                  ? 'border-l-2 border-n-slate-12 bg-n-alpha-2'
                  : ''
              "
            >
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  class="size-10 shrink-0 overflow-hidden rounded-md bg-n-alpha-2"
                  :aria-label="
                    t('CONVERSATION_SIDEBAR.NERK.EXPAND_PRODUCT_IMAGE')
                  "
                  @click="previewLine = line"
                >
                  <img
                    :src="line.imageUrl || line.image_url"
                    :alt="line.productName || line.product_name"
                    class="size-full object-cover transition hover:scale-110"
                  />
                </button>
                <div class="min-w-0 flex-1">
                  <div class="flex min-w-0 items-center gap-1.5">
                    <span
                      v-if="lineCombo(line)"
                      class="shrink-0 rounded bg-n-slate-12 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wide text-white"
                    >
                      {{ t('CONVERSATION_SIDEBAR.NERK.COMBO_BADGE') }}
                    </span>
                    <p class="truncate text-xs font-medium text-n-slate-12">
                      {{ line.productName || line.product_name }}
                    </p>
                  </div>
                  <p class="truncate text-[10px] text-n-slate-10">
                    {{ lineDetail(line) }}
                  </p>
                  <p
                    v-if="lineCombo(line)"
                    class="truncate text-[10px] font-medium text-n-slate-11"
                  >
                    {{ lineCombo(line).name }}
                  </p>
                </div>
                <div class="flex shrink-0 flex-col items-end gap-1">
                  <span
                    class="nerk-display text-xs font-semibold text-n-slate-12"
                    >{{
                      formatCurrency(
                        (line.unitPriceCents || line.unit_price_cents) *
                          line.quantity
                      )
                    }}</span
                  >
                  <div class="flex items-center gap-1">
                    <div
                      class="flex items-center rounded-md border border-n-weak bg-n-solid-1"
                    >
                      <button
                        type="button"
                        class="px-1.5 py-0.5 text-xs"
                        :aria-label="
                          t('CONVERSATION_SIDEBAR.NERK.DECREASE_QUANTITY')
                        "
                        :disabled="saving"
                        @click="changeQuantity(line, -1)"
                      >
                        {{ t('CONVERSATION_SIDEBAR.NERK.DECREASE_SYMBOL') }}
                      </button>
                      <span
                        class="min-w-5 text-center text-[10px] font-medium"
                        >{{ line.quantity }}</span
                      >
                      <button
                        type="button"
                        class="px-1.5 py-0.5 text-xs"
                        :aria-label="
                          t('CONVERSATION_SIDEBAR.NERK.INCREASE_QUANTITY')
                        "
                        :disabled="saving"
                        @click="changeQuantity(line, 1)"
                      >
                        {{ t('CONVERSATION_SIDEBAR.NERK.INCREASE_SYMBOL') }}
                      </button>
                    </div>
                    <button
                      type="button"
                      class="flex size-6 items-center justify-center rounded-md text-n-ruby-11 hover:bg-n-ruby-3"
                      :aria-label="t('CONVERSATION_SIDEBAR.NERK.REMOVE_ITEM')"
                      :disabled="saving"
                      @click="removeLine(line)"
                    >
                      <span class="i-lucide-trash-2 size-3.5" />
                    </button>
                  </div>
                </div>
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
            class="max-h-[48%] shrink-0 overflow-y-auto overscroll-contain border-t border-n-weak p-3"
          >
            <div
              class="mb-2 rounded-lg border border-n-weak bg-n-alpha-2 p-2.5"
            >
              <div class="flex items-start gap-2">
                <span
                  class="i-lucide-map-pin mt-0.5 size-4 shrink-0 text-n-slate-12"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-1.5">
                    <p
                      class="text-[9px] font-medium uppercase tracking-wide text-n-slate-10"
                    >
                      {{ t('CONVERSATION_SIDEBAR.NERK.DELIVERY_ADDRESS') }}
                    </p>
                    <span
                      v-if="
                        selectedAddress?.isDefault ||
                        selectedAddress?.is_default
                      "
                      class="rounded bg-n-slate-12 px-1.5 py-0.5 text-[8px] font-medium uppercase tracking-wide text-white"
                    >
                      {{ t('CONVERSATION_SIDEBAR.NERK.DEFAULT_ADDRESS') }}
                    </span>
                    <span
                      v-if="quote?.shipping?.fallback_reason"
                      class="i-lucide-info size-3 text-n-slate-9"
                      :title="quote.shipping.fallback_reason"
                      :aria-label="quote.shipping.fallback_reason"
                    />
                  </div>
                  <p
                    class="mt-0.5 text-[11px] font-medium leading-4 text-n-slate-12"
                  >
                    {{
                      selectedAddress
                        ? addressLabel(selectedAddress)
                        : t('CONVERSATION_SIDEBAR.NERK.ADDRESS_REQUIRED')
                    }}
                  </p>
                </div>
                <button
                  type="button"
                  class="flex shrink-0 items-center gap-1 rounded-md border border-n-weak bg-n-solid-1 px-2 py-1 text-[9px] font-medium text-n-slate-12 hover:bg-n-alpha-2"
                  :disabled="saving"
                  @click="toggleAddressPicker"
                >
                  <span
                    :class="
                      addressPickerOpen ? 'i-lucide-x' : 'i-lucide-pencil-line'
                    "
                    class="size-3"
                  />
                  {{
                    addressPickerOpen
                      ? t('CONVERSATION_SIDEBAR.NERK.CLOSE')
                      : t('CONVERSATION_SIDEBAR.NERK.CHANGE_ADDRESS')
                  }}
                </button>
              </div>

              <div
                v-if="addressPickerOpen"
                class="mt-2 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
              >
                <div class="relative border-b border-n-weak">
                  <span
                    class="i-lucide-search absolute left-2.5 top-2.5 size-3.5 text-n-slate-9"
                  />
                  <input
                    v-model="addressSearch"
                    type="search"
                    :placeholder="t('CONVERSATION_SIDEBAR.NERK.SEARCH_ADDRESS')"
                    class="w-full border-0 bg-transparent py-2 pl-8 pr-2 text-[11px] text-n-slate-12 outline-none"
                  />
                </div>
                <div class="max-h-28 overflow-y-auto overscroll-contain p-1">
                  <button
                    v-for="address in filteredAddresses"
                    :key="address.id"
                    type="button"
                    class="flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
                    :class="
                      address.id === selectedAddressId ? 'bg-n-alpha-2' : ''
                    "
                    @click="selectAddress(address.id)"
                  >
                    <span
                      class="mt-0.5 size-3.5 shrink-0"
                      :class="
                        address.id === selectedAddressId
                          ? 'i-lucide-circle-check text-n-slate-12'
                          : 'i-lucide-map-pin text-n-slate-9'
                      "
                    />
                    <span class="text-[10px] leading-4 text-n-slate-12">
                      {{ addressLabel(address) }}
                    </span>
                  </button>
                  <p
                    v-if="!filteredAddresses.length"
                    class="px-2 py-3 text-center text-[10px] text-n-slate-10"
                  >
                    {{ t('CONVERSATION_SIDEBAR.NERK.ADDRESS_NOT_FOUND') }}
                  </p>
                </div>
                <a
                  v-if="profileUrl"
                  :href="profileSectionUrl('addresses')"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center justify-center gap-1 border-t border-n-weak px-2 py-1.5 text-[10px] font-medium text-n-slate-12 hover:bg-n-alpha-2"
                >
                  <span class="i-lucide-plus size-3" />
                  {{ t('CONVERSATION_SIDEBAR.NERK.ADD_NEW_ADDRESS') }}
                </a>
              </div>

              <label
                class="mt-2 flex items-center justify-between gap-2 rounded-lg bg-n-solid-1 px-2.5 py-2"
              >
                <span class="min-w-0">
                  <span
                    class="block text-[9px] font-medium uppercase tracking-wide text-n-slate-10"
                  >
                    {{ t('CONVERSATION_SIDEBAR.NERK.SHIPPING_DISCOUNT') }}
                  </span>
                  <span class="block text-[9px] text-n-slate-9">
                    {{
                      t('CONVERSATION_SIDEBAR.NERK.SHIPPING_DISCOUNT_LIMIT', {
                        amount: formatCurrency(shippingDiscountLimitCents),
                      })
                    }}
                  </span>
                </span>
                <input
                  v-model="shippingDiscountInput"
                  type="text"
                  inputmode="decimal"
                  :disabled="!selectedAddress || saving || !lines.length"
                  class="nerk-display w-24 shrink-0 rounded-md border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-right text-xs text-n-slate-12"
                  @focus="editShippingDiscount"
                  @blur="commitShippingDiscount"
                  @keydown.enter.prevent="$event.target.blur()"
                />
              </label>
              <ComboBox
                v-if="quote?.shipping?.options?.length"
                :model-value="shippingServiceId"
                :options="shippingOptions"
                :placeholder="
                  t('CONVERSATION_SIDEBAR.NERK.SELECT_SHIPPING_SERVICE')
                "
                :search-placeholder="
                  t('CONVERSATION_SIDEBAR.NERK.SEARCH_SHIPPING_SERVICE')
                "
                :clearable="false"
                active-color="slate"
                class="mt-2 [&_button]:!px-2 [&_button]:!py-1.5 [&_button]:!text-xs"
                @update:model-value="selectShippingService"
              />
            </div>
            <label
              class="block text-[10px] uppercase tracking-wide text-n-slate-10"
            >
              {{ t('CONVERSATION_SIDEBAR.NERK.COUPON_CODE') }}
              <ComboBox
                :model-value="couponCode"
                :options="couponOptions"
                :placeholder="t('CONVERSATION_SIDEBAR.NERK.NO_COUPON')"
                :search-placeholder="
                  t('CONVERSATION_SIDEBAR.NERK.SEARCH_COUPON')
                "
                :empty-state="t('CONVERSATION_SIDEBAR.NERK.NO_COUPON_FOUND')"
                :disabled="!lines.length || saving"
                active-color="slate"
                class="mt-1 [&_button]:!px-2 [&_button]:!py-1.5 [&_button]:!text-xs"
                @update:model-value="selectCoupon"
              />
            </label>
            <dl v-if="quote" class="mt-2 space-y-1 text-xs">
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
          </div>
        </aside>
      </div>
    </div>
  </Dialog>
</template>
