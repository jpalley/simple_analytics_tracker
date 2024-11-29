// visitor-logger.js

var _hsq = (window._hsq = window._hsq || []);
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

    var uuid;

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

      uuid = getUUID();
      _hsq.push(["identify", { id: uuid }]);
      _hsq.push(['trackPageView']);
      captureUrlParameters();
      sendVisitData();
      bindEvents();
    }

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
          fbp: getFacebookPixelParameter(),
        },
      };

      sendData("visit", data);
    }
    function getFacebookPixelParameter() {
      // Get all cookies as a string
      const cookies = document.cookie.split(';');
  
      // Find the _fbp cookie
      const fbpCookie = cookies.find(cookie => cookie.trim().startsWith('_fbp='));
  
      if (fbpCookie) {
          // Extract the value of _fbp
          const [, fbpValue] = fbpCookie.split('=');
          return decodeURIComponent(fbpValue);
      }
  
      // Return null if _fbp cookie isn't found
      return null;
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

    return {
      init: init,
      trackEvent: trackEvent, // Expose the new function
      identify: identify,
    };
  })();

  // Expose VisitorLogger to the global object
  window.VisitorLogger = VisitorLogger;
})(window, document);
