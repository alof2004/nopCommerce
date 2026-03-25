import http from 'k6/http';
import { check, fail, sleep } from 'k6';
import { parseHTML } from 'k6/html';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost').replace(/\/+$/, '');
const PAYMENT_METHOD = __ENV.PAYMENT_METHOD || 'Payments.Manual';
const ADD_TO_CART_PATH = __ENV.ADD_TO_CART_PATH || '';
const CHECKOUT_COUNTRY_ID = __ENV.CHECKOUT_COUNTRY_ID || '';
const CHECKOUT_STATE_ID = __ENV.CHECKOUT_STATE_ID || '';
const THINK_TIME_SECONDS = Number(__ENV.THINK_TIME_SECONDS || '0.5');
const IMPATIENT_USER_PERCENT = Number(__ENV.IMPATIENT_USER_PERCENT || '0.30');
const NORMAL_REQUEST_TIMEOUT = __ENV.NORMAL_REQUEST_TIMEOUT || '10s';
const IMPATIENT_CONFIRM_TIMEOUT = __ENV.IMPATIENT_CONFIRM_TIMEOUT || '3s';
const STAGE_1_DURATION = __ENV.K6_STAGE_1_DURATION || '30s';
const STAGE_1_TARGET = Number(__ENV.K6_STAGE_1_TARGET || '10');
const STAGE_2_DURATION = __ENV.K6_STAGE_2_DURATION || '2m';
const STAGE_2_TARGET = Number(__ENV.K6_STAGE_2_TARGET || '15');
const STAGE_3_DURATION = __ENV.K6_STAGE_3_DURATION || '3m';
const STAGE_3_TARGET = Number(__ENV.K6_STAGE_3_TARGET || '15');
const STAGE_4_DURATION = __ENV.K6_STAGE_4_DURATION || '30s';
const STAGE_4_TARGET = Number(__ENV.K6_STAGE_4_TARGET || '0');

export const options = {
  stages: [
    { duration: STAGE_1_DURATION, target: STAGE_1_TARGET },
    { duration: STAGE_2_DURATION, target: STAGE_2_TARGET },
    { duration: STAGE_3_DURATION, target: STAGE_3_TARGET },
    { duration: STAGE_4_DURATION, target: STAGE_4_TARGET }
  ],
  thresholds: {
    http_req_failed: ['rate<0.30'],
    checks: ['rate>0.70']
  }
};

export default function () {
  resetAnonymousSession();
  const fakeIdentity = buildFakeIdentity();
  const patienceProfile = selectPatienceProfile();

  try {
    const home = getPage('/', { user_profile: patienceProfile.name });
    assertStoreReady(home);

    const antiForgeryToken = extractAntiForgeryToken(home.body);
    const addToCart = addViableHomepageProductToCart(home.body, antiForgeryToken, patienceProfile);

    check(addToCart.responseJson, {
      'product added to cart successfully': (data) => Boolean(data.success && data.updatetopcartsectionhtml)
    }) || fail(`Add-to-cart failed: ${JSON.stringify(addToCart.responseJson)}`);

    const cartPage = getPage('/cart', { step: 'cart_validation', user_profile: patienceProfile.name });
    assertCartHasItems(cartPage);
    startCheckoutFromCart(cartPage, patienceProfile);

    const checkoutPage = getPage('/checkout', { step: 'checkout_entry', user_profile: patienceProfile.name });
    assertStoreReady(checkoutPage);
    assertNotAuthenticationRedirect(checkoutPage, 'Guest checkout is disabled or checkout requires authentication.');
    assertNotCartRedirect(checkoutPage, 'Checkout redirected back to /cart because no cart items were persisted.');

    const checkoutToken = extractAntiForgeryToken(checkoutPage.body);

    let nextSectionHtml = checkoutPage.body;

    const billingPayload = {
      '__RequestVerificationToken': checkoutToken,
      'billing_address_id': '0',
      'ShipToSameAddress': 'true',
      'BillingNewAddress.Id': '0',
      'BillingNewAddress.FirstName': fakeIdentity.firstName,
      'BillingNewAddress.LastName': fakeIdentity.lastName,
      'BillingNewAddress.Email': fakeIdentity.email,
      'BillingNewAddress.Company': 'Acme Commerce',
      'BillingNewAddress.CountryId': resolveSelectedValue(nextSectionHtml, 'BillingNewAddress.CountryId', CHECKOUT_COUNTRY_ID),
      'BillingNewAddress.StateProvinceId': resolveSelectedValue(nextSectionHtml, 'BillingNewAddress.StateProvinceId', CHECKOUT_STATE_ID, true),
      'BillingNewAddress.County': '',
      'BillingNewAddress.City': fakeIdentity.city,
      'BillingNewAddress.Address1': fakeIdentity.address1,
      'BillingNewAddress.Address2': '',
      'BillingNewAddress.ZipPostalCode': fakeIdentity.zip,
      'BillingNewAddress.PhoneNumber': fakeIdentity.phone,
      'BillingNewAddress.FaxNumber': ''
    };

    let stepResponse = parseJson(postForm('/checkout/OpcSaveBilling/', billingPayload, { step: 'billing', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout), 'opc billing');
    check(stepResponse, {
      'billing step succeeded': (data) => !data.error
    }) || fail(`Billing failed: ${JSON.stringify(stepResponse)}`);

    if (stepResponse.goto_section === 'shipping') {
      nextSectionHtml = getUpdateSectionHtml(stepResponse);
      const shippingPayload = {
        '__RequestVerificationToken': checkoutToken,
        'shipping_address_id': '',
        'ShippingNewAddress.Id': '0',
        'ShippingNewAddress.FirstName': fakeIdentity.firstName,
        'ShippingNewAddress.LastName': fakeIdentity.lastName,
        'ShippingNewAddress.Email': fakeIdentity.email,
        'ShippingNewAddress.Company': 'Acme Commerce',
        'ShippingNewAddress.CountryId': resolveSelectedValue(nextSectionHtml, 'ShippingNewAddress.CountryId', CHECKOUT_COUNTRY_ID),
        'ShippingNewAddress.StateProvinceId': resolveSelectedValue(nextSectionHtml, 'ShippingNewAddress.StateProvinceId', CHECKOUT_STATE_ID, true),
        'ShippingNewAddress.County': '',
        'ShippingNewAddress.City': fakeIdentity.city,
        'ShippingNewAddress.Address1': fakeIdentity.address1,
        'ShippingNewAddress.Address2': '',
        'ShippingNewAddress.ZipPostalCode': fakeIdentity.zip,
        'ShippingNewAddress.PhoneNumber': fakeIdentity.phone,
        'ShippingNewAddress.FaxNumber': ''
      };

      stepResponse = parseJson(postForm('/checkout/OpcSaveShipping/', shippingPayload, { step: 'shipping', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout), 'opc shipping');
      check(stepResponse, {
        'shipping step succeeded': (data) => !data.error
      }) || fail(`Shipping failed: ${JSON.stringify(stepResponse)}`);
    }

    if (stepResponse.goto_section === 'shipping_method') {
      nextSectionHtml = getUpdateSectionHtml(stepResponse);
      const shippingOption = extractCheckedOrFirstRadioValue(nextSectionHtml, 'shippingoption');
      if (!shippingOption) {
        fail('No shipping option found in checkout response.');
      }

      stepResponse = parseJson(postForm('/checkout/OpcSaveShippingMethod/', {
        '__RequestVerificationToken': checkoutToken,
        shippingoption: shippingOption
      }, { step: 'shipping_method', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout), 'opc shipping method');

      check(stepResponse, {
        'shipping method step succeeded': (data) => !data.error
      }) || fail(`Shipping method failed: ${JSON.stringify(stepResponse)}`);
    }

    nextSectionHtml = getUpdateSectionHtml(stepResponse);
    const paymentMethod = extractPaymentMethod(nextSectionHtml, PAYMENT_METHOD);
    if (!paymentMethod) {
      fail(`Payment method '${PAYMENT_METHOD}' not found in checkout response.`);
    }

    stepResponse = parseJson(postForm('/checkout/OpcSavePaymentMethod/', {
      '__RequestVerificationToken': checkoutToken,
      paymentmethod: paymentMethod,
      UseRewardPoints: 'false'
    }, { step: 'payment_method', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout), 'opc payment method');

    check(stepResponse, {
      'payment method step succeeded': (data) => !data.error
    }) || fail(`Payment method selection failed: ${JSON.stringify(stepResponse)}`);

    const paymentInfoPayload = buildPaymentInfoPayload(PAYMENT_METHOD);
    stepResponse = parseJson(postForm('/checkout/OpcSavePaymentInfo/', paymentInfoPayload, { step: 'payment_info', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout), 'opc payment info');
    check(stepResponse, {
      'payment info step succeeded': (data) => !data.error
    }) || fail(`Payment info failed: ${JSON.stringify(stepResponse)}`);

    const confirmPayload = {
      '__RequestVerificationToken': checkoutToken,
      'termsofservice': 'on'
    };

    stepResponse = parseJson(postForm('/checkout/OpcConfirmOrder/', confirmPayload, { step: 'confirm_order', user_profile: patienceProfile.name }, patienceProfile.confirmTimeout), 'opc confirm order');

    check(stepResponse, {
      'confirm order returned success or redirect': (data) => Boolean(data.success || data.redirect)
    }) || fail(`Confirm order failed: ${JSON.stringify(stepResponse)}`);

    if (stepResponse.redirect) {
      const paymentRedirect = getPage(stepResponse.redirect.replace(BASE_URL, ''), { step: 'post_process_redirect', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout);
      check(paymentRedirect, {
        'post-process redirect succeeded': (response) => response.status < 400
      });
    } else {
      const completed = getPage('/checkout/completed', { step: 'completed', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout);
      check(completed, {
        'completed page returned successfully': (response) => response.status < 400
      });
    }

    sleep(THINK_TIME_SECONDS);
  } catch (error) {
    console.log(`[${patienceProfile.name}] checkout abandoned: ${error.message}`);
  }
}

function resetAnonymousSession() {
  const jar = http.cookieJar();
  jar.clear(`${BASE_URL}/`);
}

function selectPatienceProfile() {
  const impatient = ((__VU + __ITER) % 100) < Math.round(IMPATIENT_USER_PERCENT * 100);

  if (impatient) {
    return {
      name: 'impatient',
      defaultTimeout: NORMAL_REQUEST_TIMEOUT,
      confirmTimeout: IMPATIENT_CONFIRM_TIMEOUT
    };
  }

  return {
    name: 'normal',
    defaultTimeout: NORMAL_REQUEST_TIMEOUT,
    confirmTimeout: NORMAL_REQUEST_TIMEOUT
  };
}

function buildFakeIdentity() {
  const suffix = `${__VU}-${__ITER}`;

  return {
    firstName: `User${__VU}`,
    lastName: `Test${__ITER}`,
    email: `user${suffix}@example.test`,
    city: 'Lisbon',
    address1: `${100 + __VU} Test Street`,
    zip: '1000-001',
    phone: `910000${String(__VU).padStart(3, '0')}`
  };
}

function buildPaymentInfoPayload(paymentMethodSystemName) {
  if (paymentMethodSystemName === 'Payments.Manual') {
    const nextYear = String(new Date().getFullYear() + 1);

    return {
      CreditCardType: 'visa',
      CardholderName: 'Load Test Card',
      CardNumber: '4111111111111111',
      ExpireMonth: '12',
      ExpireYear: nextYear,
      CardCode: '123'
    };
  }

  return {};
}

function getPage(path, tags = {}, timeoutOverride) {
  return http.get(toAbsoluteUrl(path), {
    redirects: 10,
    timeout: timeoutOverride || NORMAL_REQUEST_TIMEOUT,
    tags: Object.assign({ flow: 'checkout', request_type: 'page' }, tags)
  });
}

function postForm(path, payload, tags = {}, timeoutOverride) {
  return http.post(toAbsoluteUrl(path), payload, {
    redirects: 10,
    timeout: timeoutOverride || NORMAL_REQUEST_TIMEOUT,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    tags: Object.assign({ flow: 'checkout', request_type: 'form_post' }, tags)
  });
}

function parseJson(response, context) {
  try {
    return response.json();
  } catch (error) {
    fail(`Failed to parse JSON for ${context}. Status: ${response.status}. URL: ${response.url}`);
  }
}

function getUpdateSectionHtml(stepResponse) {
  if (!stepResponse || !stepResponse.update_section || !stepResponse.update_section.html) {
    return '';
  }

  return stepResponse.update_section.html;
}

function assertStoreReady(response) {
  const html = response.body || '';

  if (html.includes('nopCommerce installation')) {
    fail('The store is still on /install. Complete installation before running the checkout load test.');
  }

  if (response.url.includes('/install')) {
    fail('The current response redirected to /install. Complete installation before running the checkout load test.');
  }
}

function assertNotAuthenticationRedirect(response, failureMessage) {
  if (response.url.includes('/login') || response.url.includes('/customer/login')) {
    fail(failureMessage);
  }
}

function assertNotCartRedirect(response, failureMessage) {
  if (response.url.includes('/cart')) {
    fail(failureMessage);
  }
}

function assertCartHasItems(response) {
  const html = response.body || '';

  if (response.url.includes('/cart') && html.includes('Your Shopping Cart is empty')) {
    fail('Add-to-cart did not persist any cart items.');
  }

  if (!html.includes('cart-item-row') && html.includes('Your Shopping Cart is empty')) {
    fail('Cart page shows an empty cart.');
  }
}

function startCheckoutFromCart(cartPage, patienceProfile) {
  const cartHtml = cartPage.body || '';
  const cartToken = extractAntiForgeryToken(cartHtml);
  const payload = buildCartCheckoutPayload(cartHtml, cartToken);

  const startCheckoutResponse = postForm('/cart', payload, { step: 'cart_start_checkout', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout);

  check(startCheckoutResponse, {
    'cart start checkout request succeeded': (response) => response.status < 400
  }) || fail(`Cart checkout start failed. Status: ${startCheckoutResponse.status}. URL: ${startCheckoutResponse.url}`);

  assertStoreReady(startCheckoutResponse);
}

function extractAntiForgeryToken(html) {
  const doc = parseHTML(html);
  const token = doc.find('input[name="__RequestVerificationToken"]').first().attr('value');

  if (!token) {
    fail('Could not find anti-forgery token in page HTML.');
  }

  return token;
}

function addViableHomepageProductToCart(homeHtml, antiForgeryToken, patienceProfile) {
  const candidatePaths = ADD_TO_CART_PATH ? [stripOrigin(ADD_TO_CART_PATH)] : discoverAddToCartPaths(homeHtml);
  const attempts = [];

  for (const candidatePath of candidatePaths) {
    const response = postForm(candidatePath, { __RequestVerificationToken: antiForgeryToken }, { step: 'add_to_cart', user_profile: patienceProfile.name }, patienceProfile.defaultTimeout);
    const responseJson = parseJson(response, `add-to-cart ${candidatePath}`);

    attempts.push({
      path: candidatePath,
      success: Boolean(responseJson.success),
      redirect: responseJson.redirect || '',
      hasTopCartUpdate: Boolean(responseJson.updatetopcartsectionhtml)
    });

    if (responseJson.success && responseJson.updatetopcartsectionhtml) {
      return {
        path: candidatePath,
        responseJson
      };
    }
  }

  fail(`Could not add a direct-add homepage product to cart. Attempts: ${JSON.stringify(attempts)}`);
}

function discoverAddToCartPaths(html) {
  const doc = parseHTML(html);
  const buttons = doc.find('button.product-box-add-to-cart-button');
  const paths = [];

  for (let index = 0; index < buttons.size(); index += 1) {
    const onclick = buttons.eq(index).attr('onclick') || '';
    const match = onclick.match(/AjaxCart\.addproducttocart_catalog\('([^']+)'\)/);
    if (match && match[1]) {
      paths.push(stripOrigin(match[1]));
    }
  }

  if (!paths.length) {
    fail('Could not discover any add-to-cart catalog paths from the homepage. Set ADD_TO_CART_PATH explicitly.');
  }

  return paths;
}

function buildCartCheckoutPayload(cartHtml, antiForgeryToken) {
  const doc = parseHTML(cartHtml);
  const payload = {
    __RequestVerificationToken: antiForgeryToken,
    termsofservice: 'on',
    checkout: 'checkout'
  };

  const selects = doc.find('select[name^="checkout_attribute_"]');
  for (let index = 0; index < selects.size(); index += 1) {
    const field = selects.eq(index);
    const name = field.attr('name');
    if (name && !Object.prototype.hasOwnProperty.call(payload, name)) {
      payload[name] = resolveSelectedValue(cartHtml, name, '');
    }
  }

  const inputs = doc.find('input[name^="checkout_attribute_"]');
  for (let index = 0; index < inputs.size(); index += 1) {
    const field = inputs.eq(index);
    const name = field.attr('name');
    const type = (field.attr('type') || '').toLowerCase();

    if (!name || Object.prototype.hasOwnProperty.call(payload, name)) {
      continue;
    }

    if (type === 'checkbox' || type === 'radio') {
      if (field.attr('checked')) {
        payload[name] = field.attr('value') || 'true';
      }
      continue;
    }

    payload[name] = field.attr('value') || '';
  }

  const textareas = doc.find('textarea[name^="checkout_attribute_"]');
  for (let index = 0; index < textareas.size(); index += 1) {
    const field = textareas.eq(index);
    const name = field.attr('name');
    if (name && !Object.prototype.hasOwnProperty.call(payload, name)) {
      payload[name] = field.text() || '';
    }
  }

  return payload;
}

function extractInitialSectionHtml(pageHtml, sectionName) {
  const regex = new RegExp(`<div id="checkout-${escapeRegExp(sectionName)}-load">([\\s\\S]*?)</div>`, 'i');
  const match = pageHtml.match(regex);
  return match ? match[1] : pageHtml;
}

function resolveSelectedValue(html, fieldName, overrideValue, allowEmpty = false) {
  if (overrideValue) {
    return overrideValue;
  }

  const doc = parseHTML(html);
  const select = findFieldByName(doc.find('select'), fieldName);
  if (!select || !select.size()) {
    return allowEmpty ? '' : '0';
  }

  let selected = select.find('option[selected]').first().attr('value');
  if (selected && selected !== '0') {
    return selected;
  }

  const options = select.find('option');
  for (let i = 0; i < options.size(); i += 1) {
    const value = options.eq(i).attr('value');
    if (!value) {
      continue;
    }
    if (allowEmpty && value === '0') {
      continue;
    }
    return value;
  }

  return allowEmpty ? '' : '0';
}

function extractCheckedOrFirstRadioValue(html, radioName) {
  const doc = parseHTML(html);
  let radio = findCheckedFieldByName(doc.find('input'), radioName);
  if (!radio || !radio.size()) {
    radio = findFieldByName(doc.find('input'), radioName);
  }

  return radio.attr('value') || '';
}

function extractPaymentMethod(html, preferredMethod) {
  const doc = parseHTML(html);
  const inputs = doc.find('input');
  for (let index = 0; index < inputs.size(); index += 1) {
    const input = inputs.eq(index);
    if (input.attr('name') === 'paymentmethod' && input.attr('value') === preferredMethod) {
      return input.attr('value');
    }
  }

  const first = findFieldByName(inputs, 'paymentmethod');
  return first.attr('value') || '';
}

function findFieldByName(selection, fieldName) {
  for (let index = 0; index < selection.size(); index += 1) {
    const field = selection.eq(index);
    if (field.attr('name') === fieldName) {
      return field;
    }
  }

  return null;
}

function findCheckedFieldByName(selection, fieldName) {
  for (let index = 0; index < selection.size(); index += 1) {
    const field = selection.eq(index);
    if (field.attr('name') === fieldName && field.attr('checked')) {
      return field;
    }
  }

  return null;
}

function toAbsoluteUrl(path) {
  if (!path) {
    return BASE_URL;
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  if (path.startsWith('/')) {
    return `${BASE_URL}${path}`;
  }
  return `${BASE_URL}/${path}`;
}

function stripOrigin(url) {
  return url.replace(/^https?:\/\/[^/]+/i, '');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
