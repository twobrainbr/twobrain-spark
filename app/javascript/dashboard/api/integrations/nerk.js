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

  searchProducts(query) {
    return axios.get(`${this.url}/products`, { params: { query } });
  }

  getTracking(orderId) {
    return axios.get(`${this.url}/tracking`, {
      params: { order_id: orderId },
    });
  }
}

export default new NerkAPI();
