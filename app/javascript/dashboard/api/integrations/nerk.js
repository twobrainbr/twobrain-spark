/* global axios */

import ApiClient from '../ApiClient';

class NerkAPI extends ApiClient {
  constructor() {
    super('integrations/nerk', { accountScoped: true });
  }

  getOrders(contactId) {
    return axios.get(`${this.url}/orders`, {
      params: { contact_id: contactId },
    });
  }

  getContext(contactId) {
    return axios.get(`${this.url}/context`, {
      params: { contact_id: contactId },
    });
  }

  searchProducts(query = '') {
    return axios.get(`${this.url}/products`, { params: { query } });
  }

  getCarts(contactId) {
    return axios.get(`${this.url}/carts`, {
      params: { contact_id: contactId },
    });
  }

  startNewCart(contactId) {
    return axios.post(`${this.url}/new_cart`, { contact_id: contactId });
  }

  getPromotions() {
    return axios.get(`${this.url}/promotions`);
  }

  getTracking(contactId, orderNumber) {
    return axios.get(`${this.url}/tracking`, {
      params: { contact_id: contactId, order_number: orderNumber },
    });
  }

  createAssistedOrder(contactId, lines, couponCode, cartId) {
    return axios.post(`${this.url}/assisted_order`, {
      contact_id: contactId,
      lines,
      coupon_code: couponCode,
      cart_id: cartId,
    });
  }

  updateOrder(contactId, orderId, notes) {
    return axios.patch(`${this.url}/update_order`, {
      contact_id: contactId,
      order_id: orderId,
      notes,
    });
  }

  completeLead(contactId, lead) {
    return axios.post(`${this.url}/complete_lead`, {
      contact_id: contactId,
      ...lead,
    });
  }
}

export default new NerkAPI();
