___TERMS_OF_SERVICE___

By creating or modifying this file you agree to Google Tag Manager's Community
Template Gallery Developer Terms of Service available at
https://developers.google.com/tag-manager/gallery-tos (or such other URL as
Google may provide), as modified from time to time.


___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "Trasty - Events Journey",
  "brand": {
    "id": "brand_dummy",
    "displayName": ""
  },
  "description": "",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "APIKey",
    "displayName": "API-KEY",
    "simpleValueType": true,
    "valueHint": "sjaihfa891234asndkjashf10"
  },
  {
    "type": "TEXT",
    "name": "IngestEvent",
    "displayName": "Evento",
    "simpleValueType": true
  },
  {
    "type": "CHECKBOX",
    "name": "useOptimisticScenario",
    "checkboxText": "Optmistic Scenario",
    "simpleValueType": true
  }
]


___SANDBOXED_JS_FOR_SERVER___

// ─────────────────────────────────────────────────────────────────────────────
// Trasty Pipeline — sGTM Custom Tag Template  (v1.2.0)
// ─────────────────────────────────────────────────────────────────────────────
// Mapeia eventos GA4 standard para o contrato JourneyEventPayload do backend
// Rust e envia para as rotas /v1/journey/events e /v1/identify.
//
// 📖 Documentação completa: tracker/README.md → seção "Integração sGTM"
//
// Campos configuráveis no Template Editor:
//   - APIKey                  (text)     : Chave de autenticação do cliente
//   - IngestEvent             (select)   : "track" ou "identify"
//   - useOptimisticScenario   (checkbox) : true = gtmOnSuccess imediato
//
// Variáveis necessárias no GTM Web (Fields to Set da GA4 Event Tag):
//   - trst_anon_id       ← {{LS - _trstaid}}      (localStorage)
//   - trst_journey_id    ← {{LS - _trstjid}}       (localStorage)
//   - trst_user_id       ← {{LS - _trstid}}        (localStorage)
//   - navigation_payload ← {{JS - Navigation Payload}} (JSON.stringify)
//
// Changelog:
//   v1.2.0 — NavigationPayload, toNum() sandbox-safe, forwardCookies,
//            view_item_list, resolução de identidade cross-domain
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
// isDef() protege valores numéricos zero (price=0, quantity=0) de serem
// descartados pela avaliação falsy do operador ||. Sem isso, brindes e
// fretes grátis seriam gravados como NULL no banco.
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
  // 1. Tenta ler dos parâmetros do GA4 (essencial para Cross-Domain)
  // No Web GTM, mapeie o cookie _trstaid para o parâmetro 'trst_anon_id'
  var paramId = getEventData('trst_anon_id') || getEventData(COOKIE_ANON_ID);
  if (paramId) return paramId;

  // 2. Tenta ler do Cookie header (só funciona se estiver no mesmo domínio/subdomínio)
  var vals = getCookieValues(COOKIE_ANON_ID);
  if (vals && vals.length > 0 && vals[0]) return vals[0];

  // 3. Gera novo ID persistindo por 1 ano (fallback final)
  // Alinhado com trasty.js: prefixo 'anon_'
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
  // 1. Tenta ler do parâmetro GA4 (ex: trst_user_id ou trst_journey_id)
  var paramVal = getEventData(paramKey) || getEventData(cookieName);
  if (paramVal) return paramVal;

  // 2. Tenta ler do Cookie
  var vals = getCookieValues(cookieName);
  return (vals && vals.length > 0 && vals[0]) ? vals[0] : undefined;
}

// ── Navigation Payload (enviado pelo Web GTM como event parameter) ─────────────
// No Web GTM: Variável JavaScript = window.__pixelNavigationPayload__
// Nome do parâmetro no GA4 Config/Event Tag: navigation_payload

function extractNavigation() {
  var nav = getEventData('navigation_payload');
  
  // Se o GTM Web enviou como JSON.stringify (recomendado para evitar "[object Object]")
  if (getType(nav) === 'string') {
    if (nav === '[object Object]') {
      logToConsole('[Trasty] Erro: navigation_payload chegou como "[object Object]". Verifique o GTM Web (use JSON.stringify).');
      return undefined;
    }
    nav = JSON.parse(nav);
  }

  return getType(nav) === 'object' ? nav : undefined;
}

// ── Extração de produto (GA4 items[0]) ────────────────────────────────────────

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

// ── Helper numérico (sandbox-safe) ───────────────────────────────────────────
// Number() e isNaN() NÃO estão disponíveis no sGTM Sandbox.
// (v - 0) é equivalente a Number(v); (n === n) é falso apenas para NaN.

function toNum(v) {
  var n = v - 0;
  return n === n ? n : undefined; // undefined se NaN
}

// ── Extração de carrinho (GA4 items[]) ────────────────────────────────────────

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
  // Força conversão numérica — VTEX pode enviar value/discount como string
  var cartTotal = isDef(cartValue)    ? toNum(cartValue)    : undefined;
  var cartDsc   = isDef(cartDiscount) ? toNum(cartDiscount) : undefined;
  return {
    items:       mappedItems,
    items_count: mappedItems.length,
    total:       (cartTotal !== undefined) ? cartTotal : undefined,
    discount:    (cartDsc   !== undefined) ? cartDsc   : undefined,
  };
}

// ── Proxy de Cookies (Set-Cookie da pipeline → Browser) ─────────────────────
// O Rust retorna Set-Cookie para o sGTM (quem fez o request HTTP interno).
// O browser NUNCA vê esses headers diretamente — precisamos repassá-los
// via setCookie do sGTM, que escreve no contexto do container server-side.

function forwardCookies(headers) {
  if (!headers) return;

  // Cookies Trasty gerenciados pelo backend
  var managed = [COOKIE_JOURNEY_ID, COOKIE_TRASTY_ID, COOKIE_ANON_ID];

  for (var i = 0; i < managed.length; i++) {
    var name = managed[i];
    var headerVal = headers['set-cookie'] || headers['Set-Cookie'];
    if (!headerVal) continue;

    // set-cookie pode vir como string (header único) ou array (múltiplos Set-Cookie)
    var entries = getType(headerVal) === 'string' ? [headerVal] : headerVal;

    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j];
      // Verifica se este set-cookie é do cookie que estamos buscando
      if (entry.indexOf(name + '=') !== 0) continue;

      // Extrai apenas o valor (antes do primeiro ';')
      var parts = entry.split(';');
      var kv    = parts[0]; // ex: "_trstjid=jrn_abc123"
      var val   = kv.split('=').slice(1).join('='); // valor após '='

      // Extrai Max-Age se presente
      var maxAge = 2592000; // 30 dias (padrão backend)
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

// ── Extração de UTMs (prioridade: navigation_payload > event_data) ──────────────

function extractUtm() {
  var nav = extractNavigation();
  var lp  = nav && nav.acquisition && nav.acquisition.landing_params;
  
  // Tenta extrair UTMs do payload de navegação (client-side) ou parâmetros diretos do GA4
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
// Backend exige _trstaid no Cookie header para associar a identidade ao anon_id.

function sendIdentify() {
  var anonId = resolveAnonId();

  // Tenta extrair email de múltiplas origens possíveis
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

  // /v1/identify resolve _trstaid pelo header Cookie (req.cookie() no Rust)
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

  // Encaminha o IP real do visitante para a pipeline API via header customizado.
  // A API só aceita este header quando CF-Connecting-IP bate com um IP de sGTM
  // conhecido — isso impede spoofing por clientes externos.
  var clientIp = getRemoteAddress();
  if (clientIp) {
    headers['X-Trasty-Visitor-IP'] = clientIp;
  }

  return headers;
}


___SERVER_PERMISSIONS___

[
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
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
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
            "string": "debug"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
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
                    "string": "_trstaid"
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
                    "string": "any"
                  },
                  {
                    "type": 1,
                    "string": "any"
                  }
                ]
              },
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
                    "string": "_trstid"
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
                    "string": "any"
                  },
                  {
                    "type": 1,
                    "string": "any"
                  }
                ]
              },
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
                    "string": "_trstjid"
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
                    "string": "any"
                  },
                  {
                    "type": 1,
                    "string": "any"
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_event_data",
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
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
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
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "read_request",
        "versionId": "1"
      },
      "param": [
        {
          "key": "requestAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "headerAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        },
        {
          "key": "queryParameterAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios: []


___NOTES___

Created on 21/05/2026, 10:44:31


