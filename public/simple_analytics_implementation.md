# Simple Analytics Tracker Implementation Guide

## Quick Start

To implement the Simple Analytics Tracker on your website, add the following code to the `<head>` section of your HTML:

```html
<!-- Simple Analytics Tracker Setup -->
<script>
  // Generate or retrieve visitor UUID before script loads
  (function() {
    function generateUUID() {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
        /[xy]/g,
        function (c) {
          var r = (Math.random() * 16) | 0,
            v = c === "x" ? r : (r & 0x3) | 0x8;
          return v.toString(16);
        }
      );
    }
    
    // Initialize or retrieve UUID from localStorage
    var visitorUUID = localStorage.getItem("visitor_uuid");
    if (!visitorUUID) {
      visitorUUID = generateUUID();
      localStorage.setItem("visitor_uuid", visitorUUID);
    }
    
    // Make UUID globally available immediately
    window.VISITOR_UUID = visitorUUID;
    window.getVisitorUUID = function() {
      return visitorUUID;
    };
  })();
</script>

<!-- Then load the analytics script -->
<script src="https://your-domain.com/simple_analytics.js" async defer></script>
```

## Initialization

Initialize the tracker by adding this script at the end of your HTML body:

```html
<script>
  // Initialize the VisitorLogger with your configuration
  document.addEventListener('DOMContentLoaded', function() {
    VisitorLogger.init({
      serverUrl: 'https://analytics.clever-builds.com/',
      enableScrollDepth: true,
      enableEventLogging: true,
      customParameters: ['rfid'] // Add any custom URL parameters you want to track
    });
  });
</script>
```

## Advanced Usage

### Accessing the Visitor UUID

The visitor UUID is available immediately, even before the tracking script loads:

```javascript
// Access the UUID directly
var visitorId = window.VISITOR_UUID;
console.log("Current visitor ID:", visitorId);

// Or use the getter function
var visitorId = window.getVisitorUUID();
```

### Tracking Custom Events

You can track custom events using the following method:

```javascript
VisitorLogger.trackEvent('button_click', {
  buttonId: 'signup-button',
  buttonText: 'Sign Up Now'
});
```

### Identifying Users

You can associate user information with the visitor:

```javascript
VisitorLogger.identify({
  email: 'user@example.com',
  name: 'John Doe',
  plan: 'premium'
});
```

## Configuration Options

When initializing the tracker, you can configure the following options:

- `serverUrl` (required): The URL of your analytics server
- `enableScrollDepth`: Set to `true` to track how far users scroll on your pages
- `enableEventLogging`: Set to `true` to enable additional event logging
- `customParameters`: An array of custom URL parameters you want to track

## Hubspot Integration

The tracker automatically looks for and sends the Hubspot tracking cookie (`hubspotutk`) if it's available on your site.

## Technical Details

The script:
- Generates a visitor UUID before the tracking script loads
- Loads the tracking script asynchronously to avoid blocking page rendering
- Automatically tracks page visits and user interactions
- Captures UTM parameters and other tracking parameters from URLs
- Sends all data to your specified analytics server endpoint 