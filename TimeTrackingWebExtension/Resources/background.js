// The background script of the Safari web extension (spec_ios.md §9.5).
// Non-persistent: it forwards tab activations and completed loads or URL
// changes to the native handler as {url, time}; the handler applies the
// exclusions. Titles are never sent.

function forward(url) {
    if (!url || !(url.startsWith("http://") || url.startsWith("https://"))) {
        return;
    }
    browser.runtime.sendNativeMessage("application.id", { url: url, time: Date.now() });
}

browser.tabs.onActivated.addListener((activeInfo) => {
    browser.tabs.get(activeInfo.tabId).then((tab) => forward(tab.url));
});

browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
    if (!tab.active) {
        return;
    }
    if (changeInfo.status === "complete" || changeInfo.url) {
        forward(changeInfo.url || tab.url);
    }
});
