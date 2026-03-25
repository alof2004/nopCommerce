import { runCheckoutFlow } from './checkout-observability.js';

const FIXED_VUS = Number(__ENV.K6_FIXED_VUS || '1');
const FIXED_DURATION = __ENV.K6_FIXED_DURATION || '3m';
const FAILURE_ADD_TO_CART_PATH = __ENV.FAILURE_ADD_TO_CART_PATH || '/addproducttocart/catalog/18/1/1';

export const options = {
  vus: FIXED_VUS,
  duration: FIXED_DURATION,
  thresholds: {
    http_req_failed: ['rate<0.50']
  }
};

export default function () {
  runCheckoutFlow({
    addToCartPath: FAILURE_ADD_TO_CART_PATH,
    expectFailure: true,
    failureContext: 'minimum subtotal checkout',
    thinkTimeSeconds: 0
  });
}
