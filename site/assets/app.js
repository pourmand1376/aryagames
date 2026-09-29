// Put the visitor's platform first in the download list and name it on the hero button.
(function () {
  var ua = navigator.userAgent || "";
  var hint = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  var platform =
    /Android/i.test(ua) ? "android" :
    /iPhone|iPad|iPod/i.test(ua) || (/Mac/i.test(hint) && navigator.maxTouchPoints > 1) ? "ios" :
    /Win/i.test(hint) || /Windows/i.test(ua) ? "windows" :
    /Mac/i.test(hint) || /Macintosh/i.test(ua) ? "macos" :
    /Linux|X11/i.test(hint + ua) ? "linux" : null;
  if (!platform) return;

  var card = document.querySelector('.dl-card[data-platform="' + platform + '"]');
  if (!card) return;
  card.classList.add("here");

  var title = card.querySelector("h3");
  var hero = document.getElementById("hero-download");
  if (hero && title && !card.classList.contains("soon")) {
    hero.textContent = "دانلود برای " + title.textContent;
  }
})();

// "چطور؟" on the Mac card opens the Mac help before jumping to it.
document.addEventListener("click", function (e) {
  var link = e.target.closest && e.target.closest("[data-open]");
  if (!link) return;
  var box = document.getElementById(link.getAttribute("data-open"));
  if (box) box.open = true;
});
