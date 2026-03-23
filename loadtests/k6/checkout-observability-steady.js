import checkoutFlow from './checkout-observability.js';

const FIXED_VUS = Number(__ENV.K6_FIXED_VUS || '5');
const FIXED_DURATION = __ENV.K6_FIXED_DURATION || '24h';

export const options = {
  vus: FIXED_VUS,
  duration: FIXED_DURATION,
  thresholds: {
    http_req_failed: ['rate<0.10'],
    checks: ['rate>0.90']
  }
};

export default checkoutFlow;
