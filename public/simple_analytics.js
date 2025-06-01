// visitor-logger.js

(function (window, document) {
  "use strict";

  var VisitorLogger = (function () {
    var config = {
      serverUrl: "",
      enableScrollDepth: false,
      enableEventLogging: false,
      customParameters: [],
    };

    var defaultParameters = [
      "utm_source",
      "utm_medium",
      "utm_campaign",
      "utm_term",
      "utm_content",
      "utm_campaign_id",
      "gclid",
      "gbraid",
      "fbclid",
      "msclkid",
    ];

    // Get the UUID from the global scope or use the existing one from localStorage
    var uuid = (window.VISITOR_UUID) ? window.VISITOR_UUID : getUUID();

    function getUUID() {
      var storedUuid = localStorage.getItem("visitor_uuid");
      if (!storedUuid) {
        storedUuid = generateUUID();
        localStorage.setItem("visitor_uuid", storedUuid);
      }
      return storedUuid;
    }

    function generateUUID() {
      // Simple UUID generator
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
        /[xy]/g,
        function (c) {
          var r = (Math.random() * 16) | 0,
            v = c === "x" ? r : (r & 0x3) | 0x8;
          return v.toString(16);
        }
      );
    }

    function init(options) {
      // Merge user options with default config
      for (var key in options) {
        if (options.hasOwnProperty(key)) {
          config[key] = options[key];
        }
      }

      if (!config.serverUrl) {
        console.error("VisitorLogger: serverUrl is required.");
        return;
      }

      captureUrlParameters();
      sendVisitData();
      bindEvents();
      
      // Setup email field monitoring
      monitorEmailFields();
      
      // Check for Hubspot cookie immediately and periodically
      checkHubspotCookie();
      
      // Check for Facebook pixel cookie immediately and periodically
      checkFacebookPixel();
    }

    function captureUrlParameters() {
      var params = new URLSearchParams(window.location.search);
      var capturedParams = {};
      var allParameters = defaultParameters.concat(config.customParameters);
      allParameters.forEach(function (param) {
        var value = params.get(param);
        if (value) {
          capturedParams[param] = value;
        }
      });
      return capturedParams;
    }
    
    // Add this new function to capture all URL parameters
    function getAllUrlParams() {
      var params = new URLSearchParams(window.location.search);
      var allParams = {};
      for (var pair of params.entries()) {
        allParams[pair[0]] = pair[1];
      }
      return allParams;
    }

    function sendVisitData() {
      var data = {
        uuid: uuid,
        event_type: "visit",
        event_data: {
          url: window.location.href,
          host: window.location.host,
          path: window.location.pathname,
          protocol: window.location.protocol,
          referrer: document.referrer,
          js_user_agent: navigator.userAgent,
          language: navigator.language,
          screen_width: window.screen.width,
          screen_height: window.screen.height,
          selected_params: captureUrlParameters(),
          all_params: getAllUrlParams(),
        },
      };

      sendData("visit", data);
    }
    
    function getFacebookPixelParameter() {
      // Get all cookies as a string
      var cookies = document.cookie.split(';');
  
      // Find the _fbp cookie
      var fbpCookie = cookies.find(function(cookie) {
        return cookie.trim().startsWith('_fbp=');
      });
  
      if (fbpCookie) {
          // Extract the value of _fbp
          var fbpValue = fbpCookie.split('=')[1];
          return decodeURIComponent(fbpValue);
      }
  
      // Return null if _fbp cookie isn't found
      return null;
    }
    
    // Function to monitor all email fields, including dynamically added ones
    function monitorEmailFields() {
      // Initial setup for all existing email fields
      var emailFields = document.querySelectorAll('input[type="email"]');
      emailFields.forEach(attachEmailListener);
      
      // Setup a MutationObserver to watch for dynamically added email fields
      var observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          if (mutation.addedNodes && mutation.addedNodes.length > 0) {
            for (var i = 0; i < mutation.addedNodes.length; i++) {
              var node = mutation.addedNodes[i];
              // Check if the node is an element
              if (node.nodeType === 1) {
                // If it's an email input itself
                if (node.tagName === 'INPUT' && node.type === 'email') {
                  attachEmailListener(node);
                }
                // Check for any email inputs within the added node
                var emailInputs = node.querySelectorAll('input[type="email"]');
                emailInputs.forEach(attachEmailListener);
              }
            }
          }
        });
      });
      
      // Start observing the entire document
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    }
    
    // Function to attach input event listeners to email fields
    function attachEmailListener(emailField) {
      emailField.addEventListener('input', function(event) {
        var email = event.target.value.toLowerCase();
        if (email && email.includes('@')) {
          identify({ email: email });
        }
      });
    }
    
    function bindEvents() {
      // Click events
      document.addEventListener("click", function (event) {
        var data = {
          uuid: uuid,
          event_type: "click",
          event_data: {
            element: event.target.tagName,
            id: event.target.id,
            classes: event.target.className,
          },
        };
        sendData("event", data);
      });

      // Scroll depth
      if (config.enableScrollDepth) {
        var maxScrollDepth = 0;
        window.addEventListener("scroll", function () {
          var scrollDepth = Math.round(
            ((window.scrollY + window.innerHeight) /
              document.body.scrollHeight) *
              100
          );
          // Only track if the new scroll depth is at least 10% more than the previous max
          if (scrollDepth >= maxScrollDepth + 10) {
            maxScrollDepth = Math.floor(scrollDepth / 10) * 10; // Round down to nearest 10%
            var data = {
              uuid: uuid,
              event_type: "scroll",
              event_data: {
                scroll_depth: maxScrollDepth,
              },
            };
            sendData("event", data);
          }
        });
      }

      // Additional event logging placeholder
      if (config.enableEventLogging) {
        // Extend as needed
      }
    }

    function sendData(endpoint, data) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", config.serverUrl + "track/event", true);
      xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
      xhr.send(JSON.stringify(data));
    }
    
    function getCookie(name) {
      var value = "; " + document.cookie;
      var parts = value.split("; " + name + "=");
      if (parts.length > 1) return parts[1].split(";")[0];
      return null;
    }
    
    // Hubspot cookie check logic
    var hubspotCookieInterval;
    var facebookPixelInterval;
    
    function checkHubspotCookie() {
      var hubspotutk = getCookie('hubspotutk');
      if (hubspotutk) {
        identify({ hubspotutk: hubspotutk });
        if (hubspotCookieInterval) {
          clearInterval(hubspotCookieInterval);
        }
      } else {
        // If not found, set up an interval to check for it
        if (!hubspotCookieInterval) {
          hubspotCookieInterval = setInterval(checkHubspotCookie, 100);
        }
      }
    }
    
    function checkFacebookPixel() {
      var fbpValue = getFacebookPixelParameter();
      if (fbpValue) {
        identify({ fbp: fbpValue });
        if (facebookPixelInterval) {
          clearInterval(facebookPixelInterval);
        }
      } else {
        // If not found, set up an interval to check for it
        if (!facebookPixelInterval) {
          facebookPixelInterval = setInterval(checkFacebookPixel, 100);
        }
      }
    }

    function identify(params) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", config.serverUrl + "track/identify", true);
      xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
      var data = {
        uuid: uuid,
        properties: params,
      };
      xhr.send(JSON.stringify(data));
    }

    // New function to track custom events
    function trackEvent(eventName, eventData) {
      var data = {
        uuid: uuid,
        event_type: eventName,
        event_data: eventData || {},
      };
      sendData("event", data);
    }

    // Expose the getter function for other scripts
    window.getVisitorUUID = function() {
      return uuid;
    };

    return {
      init: init,
      trackEvent: trackEvent,
      identify: identify,
    };
  })();

  // Expose VisitorLogger to the global object
  window.VisitorLogger = VisitorLogger;
  
  // Auto-initialize if configuration is provided
  if (typeof window.VisitorLoggerConfig !== 'undefined') {
    VisitorLogger.init(window.VisitorLoggerConfig);
  }
})(window, document);
