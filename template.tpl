___INFO___

{
  "type": "TAG",
  "id": "cvt_trasty_pipeline",
  "displayName": "Trasty Pipeline Ingestion",
  "categories": [
    "ANALYTICS"
  ],
  "brand": {
    "id": "brand_trasty",
    "displayName": "Trasty"
  },
  "description": "Envia eventos de jornada normalizados do GA4 para a API do Trasty Pipeline.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "APIKey",
    "displayName": "Chave de API (APIKey)",
    "simpleValueType": "STRING",
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ],
    "help": "Insira a chave pública de API obtida no painel da Trasty (ex: pk_live_...)."
  },
  {
    "type": "SELECT",
    "name": "IngestEvent",
    "displayName": "Modo de Ingestão",
    "selectItems": [
      {
        "value": "track",
        "displayValue": "Track (Eventos de Jornada)"
      },
      {
        "value": "identify",
        "displayValue": "Identify (Identificação do Usuário)"
      }
    ],
    "simpleValueType": "STRING",
    "defaultValue": "track",
    "help": "Selecione 'Track' para enviar eventos normais (page_view, add_to_cart, purchase, etc) ou 'Identify' para mapear a identidade do usuário (e-mail)."
  },
  {
    "type": "CHECKBOX",
    "name": "useOptimisticScenario",
    "displayName": "Usar Cenário Otimista (Async)",
    "checkboxText": "Retornar sucesso imediatamente ao GTM, sem aguardar resposta da API",
    "simpleValueType": "BOOLEAN",
    "defaultValue": true,
    "help": "Recomendado para menor latência na jornada do usuário."
  }
]


___SANDBOXED_JS_CODE___

// ─────────────────────────────────────────────────────────────────────────────
// Trasty Pipeline — sGTM Custom Tag Template  (v1.2.1)
// ─────────────────────────────────────────────────────────────────────────────
const sendHttpRequest    = require('sendHttpRequest');
const getEventData       = require('getEventData');
const JSON               = require('JSON');
const getCookieValues    = require('getCookieValues');
const setCookie          = require('setCookie');
const generateRandom     = require('generateRandom');
const logToConsole       = require('logToConsole');
const getType            = require('getType');
const getTimestampMillis = require('getTimestampMillis');
const getRemoteAddress   = require('getRemoteAddress');

// ── Constantes ─────────────────────────────────────────────────────────────────
var COOKIE_ANON_ID    = '_trstaid';
var COOKIE_TRASTY_ID  = '_trstid';
var COOKIE_JOURNEY_ID = '_trstjid';
var SCHEMA_VERSION    = 1;
var BASE_URL          = 'https://pipeline.trasty.io';

// ── Helpers ────────────────────────────────────────────────────────────────────
function isDef(val) {
  return getType(val) !== 'undefined' && val !== null;
}

// ── Mapeamento GA4 → Trasty ────────────────────────────────────────────────────
var EVENT_MAP = {
  'page_view':        'page_view',
  'view_item':        'product_view',
  'add_to_cart':      'add_to_cart',
  'remove_from_cart': 'remove_from_cart',
  'view_item_list':   'view_item_list',
  'select_item':      'shelf_item_click',
  'search':           'search',
  'view_cart':        'view_cart',
  'begin_checkout':   'begin_checkout',
  'purchase':         'purchase',
};

// ── Entry point ────────────────────────────────────────────────────────────────
var ga4EventName = getEventData('event_name');
var ingestEvent  = data.IngestEvent;

logToConsole('[Trasty] event: ' + ga4EventName + ' | mode: ' + ingestEvent);

if (ingestEvent === 'identify') {
  sendIdentify();
} else if (ingestEvent === 'track') {
  var trstyEventName = EVENT_MAP[ga4EventName];
  if (!trstyEventName) {
    logToConsole('[Trasty] Evento não mapeado, ignorando: ' + ga4EventName);
    data.gtmOnSuccess();
  } else {
    sendJourneyEvent(trstyEventName);
  }
} else {
  data.gtmOnSuccess();
}

// ── Resolução de identidade ────────────────────────────────────────────────────
function resolveAnonId() {
  var paramId = getEventData('trst_anon_id') || getEventData(COOKIE_ANON_ID);
  if (paramId) return paramId;

  var vals = getCookieValues(COOKIE_ANON_ID);
  if (vals && vals.length > 0 && vals[0]) return vals[0];

  var newId = 'anon_' + getTimestampMillis() + '_' + generateRandom(100000, 999999);
  setCookie(COOKIE_ANON_ID, newId, {
    'max-age': 60 * 60 * 24 * 365,
    path: '/',
    secure: true,
    httpOnly: false,
    sameSite: 'None',
  });
  return newId;
}

function readId(paramKey, cookieName) {
  var paramVal = getEventData(paramKey) || getEventData(cookieName);
  if (paramVal) return paramVal;

  var vals = getCookieValues(cookieName);
  return (vals && vals.length > 0 && vals[0]) ? vals[0] : undefined;
}

// ── Navigation Payload ─────────────────────────────────────────────────────────
function extractNavigation() {
  var nav = getEventData('navigation_payload');
  if (getType(nav) === 'string') {
    if (nav === '[object Object]') {
      logToConsole('[Trasty] Erro: navigation_payload é "[object Object]".');
      return undefined;
    }
    nav = JSON.parse(nav);
  }
  return getType(nav) === 'object' ? nav : undefined;
}

// ── Extração de produto ────────────────────────────────────────────────────────
function extractProduct() {
  var items = getEventData('items');
  if (!items || !items.length) return undefined;
  var item = items[0];
  return {
    product_id:  item.item_id       || undefined,
    sku:         item.item_id       || undefined,
    name:        item.item_name     || undefined,
    category:    item.item_category || undefined,
    brand:       item.item_brand    || undefined,
    quantity:    isDef(item.quantity) ? item.quantity : undefined,
    unit_price:  isDef(item.price)   ? item.price   : undefined,
    total_price: (isDef(item.price) && isDef(item.quantity))
                   ? item.price * item.quantity
                   : undefined,
  };
}

// ── Helper numérico ───────────────────────────────────────────────────────────
function toNum(v) {
  var n = v - 0;
  return n === n ? n : undefined;
}

// ── Extração de carrinho ───────────────────────────────────────────────────────
function extractCart() {
  var items = getEventData('items');
  if (!items || !items.length) return undefined;

  var mappedItems = [];
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    var itPrice = isDef(it.price)    ? toNum(it.price)    : undefined;
    var itQty   = isDef(it.quantity) ? toNum(it.quantity) : undefined;
    mappedItems.push({
      product_id:  it.item_id   || undefined,
      sku:         it.item_id   || undefined,
      name:        it.item_name || undefined,
      quantity:    (itQty   !== undefined) ? itQty   : undefined,
      unit_price:  (itPrice !== undefined) ? itPrice : undefined,
      total_price: (itPrice !== undefined && itQty !== undefined) ? itPrice * itQty : undefined,
    });
  }

  var cartValue    = getEventData('value');
  var cartDiscount = getEventData('discount');
  var cartTotal = isDef(cartValue)    ? toNum(cartValue)    : undefined;
  var cartDsc   = isDef(cartDiscount) ? toNum(cartDiscount) : undefined;
  return {
    items:       mappedItems,
    items_count: mappedItems.length,
    total:       (cartTotal !== undefined) ? cartTotal : undefined,
    discount:    (cartDsc   !== undefined) ? cartDsc   : undefined,
  };
}

// ── Proxy de Cookies ───────────────────────────────────────────────────────────
function forwardCookies(headers) {
  if (!headers) return;
  var managed = [COOKIE_JOURNEY_ID, COOKIE_TRASTY_ID, COOKIE_ANON_ID];

  for (var i = 0; i < managed.length; i++) {
    var name = managed[i];
    var headerVal = headers['set-cookie'] || headers['Set-Cookie'];
    if (!headerVal) continue;

    var entries = getType(headerVal) === 'string' ? [headerVal] : headerVal;
    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j];
      if (entry.indexOf(name + '=') !== 0) continue;

      var parts = entry.split(';');
      var kv    = parts[0];
      var val   = kv.split('=').slice(1).join('=');

      var maxAge = 2592000;
      for (var k = 1; k < parts.length; k++) {
        var attr = parts[k].trim();
        if (attr.indexOf('Max-Age=') === 0) {
          maxAge = attr.split('=')[1];
        }
      }

      logToConsole('[Trasty] Forwarding cookie: ' + name + '=' + val);
      setCookie(name, val, {
        'max-age': maxAge,
        path: '/',
        secure: true,
        httpOnly: true,
        sameSite: 'None',
      });
    }
  }
}

// ── Extração de UTMs ───────────────────────────────────────────────────────────
function extractUtm() {
  var nav = extractNavigation();
  var lp  = nav && nav.acquisition && nav.acquisition.landing_params;
  
  var source   = (lp && lp.utm_source)   || getEventData('utm_source')   || getEventData('campaign_source');
  var medium   = (lp && lp.utm_medium)   || getEventData('utm_medium')   || getEventData('campaign_medium');
  var campaign = (lp && lp.utm_campaign) || getEventData('utm_campaign') || getEventData('campaign_name');

  return {
    utm_source:   source   || undefined,
    utm_medium:   medium   || undefined,
    utm_campaign: campaign || undefined,
  };
}

// ── POST /v1/journey/events ────────────────────────────────────────────────────
function sendJourneyEvent(trstyEventName) {
  var anonId    = resolveAnonId();
  var trstyId   = readId('trst_user_id',    COOKIE_TRASTY_ID);
  var journeyId = readId('trst_journey_id', COOKIE_JOURNEY_ID);
  var utm       = extractUtm();

  var payload = {
    schema_version: SCHEMA_VERSION,
    event_name:     trstyEventName,
    anon_id:        anonId,
    journey_id:     journeyId,
    trasty_id:      trstyId,
    product:        extractProduct(),
    cart:           extractCart(),
    utm_source:     utm.utm_source,
    utm_medium:     utm.utm_medium,
    utm_campaign:   utm.utm_campaign,
    navigation:     extractNavigation(),
  };

  logToConsole('[Trasty] journey payload: ' + JSON.stringify(payload));

  sendHttpRequest(
    BASE_URL + '/v1/journey/events',
    function(statusCode, responseHeaders, body) {
      logToConsole('[Trasty] journey response: ' + statusCode + ' ' + body);
      forwardCookies(responseHeaders);
      if (!data.useOptimisticScenario) {
        if (statusCode >= 200 && statusCode < 300) {
          data.gtmOnSuccess();
        } else {
          data.gtmOnFailure();
        }
      }
    },
    { headers: buildHeaders(), method: 'POST' },
    JSON.stringify(payload)
  );

  if (data.useOptimisticScenario) data.gtmOnSuccess();
}

// ── POST /v1/identify ──────────────────────────────────────────────────────────
function sendIdentify() {
  var anonId = resolveAnonId();
  var email = getEventData('email')
           || getEventData('user_data.email_address')
           || undefined;

  if (!email) {
    logToConsole('[Trasty] identify ignorado: sem email disponível');
    data.gtmOnSuccess();
    return;
  }

  var payload = {
    email: email,
    name:  getEventData('user_data.name')         || undefined,
    phone: getEventData('user_data.phone_number')  || undefined,
  };

  var identifyHeaders = buildHeaders();
  identifyHeaders['Cookie'] = COOKIE_ANON_ID + '=' + anonId;

  logToConsole('[Trasty] identify payload: ' + JSON.stringify(payload));

  sendHttpRequest(
    BASE_URL + '/v1/identify',
    function(statusCode, headers, body) {
      logToConsole('[Trasty] identify response: ' + statusCode + ' ' + body);
      if (statusCode >= 200 && statusCode < 300) {
        data.gtmOnSuccess();
      } else {
        data.gtmOnFailure();
      }
    },
    { headers: identifyHeaders, method: 'POST' },
    JSON.stringify(payload)
  );
}

// ── Headers base ───────────────────────────────────────────────────────────────
function buildHeaders() {
  var headers = {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
    'APIKey':       data.APIKey,
  };

  var clientIp = getRemoteAddress();
  if (clientIp) {
    headers['X-Trasty-Visitor-IP'] = clientIp;
  }

  return headers;
}


___OBJECT_INTEGRATION___

{
  "simpleSavedFlowConstraints": {
    "permissions": [
      {
        "instance": {
          "key": {
            "publicId": "send_http",
            "versionId": "1"
          },
          "param": [
            {
              "key": "allowedUrls",
              "value": {
                "type": 2,
                "listItem": [
                  {
                    "type": 1,
                    "string": "https://pipeline.trasty.io/*"
                  }
                ]
              }
            }
          ]
        }
      },
      {
        "instance": {
          "key": {
            "publicId": "get_event_data",
            "versionId": "1"
          },
          "param": [
            {
              "key": "eventDataAccess",
              "value": {
                "type": 1,
                "string": "any"
              }
            }
          ]
        }
      },
      {
        "instance": {
          "key": {
            "publicId": "get_cookies",
            "versionId": "1"
          },
          "param": [
            {
              "key": "cookieAccess",
              "value": {
                "type": 1,
                "string": "any"
              }
            }
          ]
        }
      },
      {
        "instance": {
          "key": {
            "publicId": "set_cookies",
            "versionId": "1"
          },
          "param": [
            {
              "key": "allowedCookies",
              "value": {
                "type": 2,
                "listItem": [
                  {
                    "type": 3,
                    "mapKey": [
                      {
                        "type": 1,
                        "string": "name"
                      },
                      {
                        "type": 1,
                        "string": "domain"
                      },
                      {
                        "type": 1,
                        "string": "path"
                      },
                      {
                        "type": 1,
                        "string": "secure"
                      },
                      {
                        "type": 1,
                        "string": "session"
                      }
                    ],
                    "mapValue": [
                      {
                        "type": 1,
                        "string": "*"
                      },
                      {
                        "type": 1,
                        "string": "*"
                      },
                      {
                        "type": 1,
                        "string": "*"
                      },
                      {
                        "type": 1,
                        "string": "*"
                      },
                      {
                        "type": 1,
                        "string": "*"
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
      },
      {
        "instance": {
          "key": {
            "publicId": "logging",
            "versionId": "1"
          },
          "param": [
            {
              "key": "environments",
              "value": {
                "type": 1,
                "string": "all"
              }
            }
          ]
        }
      },
      {
        "instance": {
          "key": {
            "publicId": "get_remote_address",
            "versionId": "1"
          },
          "param": []
        }
      }
    ]
  }
}
