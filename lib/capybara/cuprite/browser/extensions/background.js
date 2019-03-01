chrome.runtime.onInstalled.addListener(function() {
  chrome.proxy.settings.set(
    {value: { mode: "direct" }, scope: "regular"},
    function() {});

  console.log("onInstalled");
});

chrome.runtime.onMessage.addListener(function(data, sender, sendResponse) {
  if (data.ip && data.port) {
    console.log("Rotating proxy");

    let config = {
      mode: "fixed_servers",
      rules: {
        singleProxy: {
          scheme: "http",
          host: data.ip,
          port: data.port
        },
        bypassList: []
      }
    };

    chrome.proxy.settings.set(
      {value: config, scope: 'regular'},
      function() {});
  } else {
    chrome.proxy.settings.set(
      {value: { mode: "direct" }, scope: "regular"},
      function() {});
  }

  sendResponse("ok");
});
