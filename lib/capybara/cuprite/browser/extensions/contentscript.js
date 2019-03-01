window.addEventListener("message", function(event) {
  if (event.source != window)
    return;

  let data = event.data;
  if (data.type == "rotateProxy") {
    console.log(`Content script received: ${data.ip}:${data.port}`);
    chrome.runtime.sendMessage(data, function(response) {
      console.log(response);
    });
  }
}, false);
