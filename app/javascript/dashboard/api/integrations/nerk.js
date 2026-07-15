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

  searchProducts(query) {
    return axios.get(`${this.url}/products`, { params: { query } });
  }

  getTracking(contactId, orderNumber) {
    return axios.get(`${this.url}/tracking`, {
      params: { contact_id: contactId, order_number: orderNumber },
    });
  }
}

export default new NerkAPI();
