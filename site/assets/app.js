// The hero fan plays out the start of a Hokm deal: you get five cards, call Hokm with one of four suit buttons, and
// the other eight come from the 47 left (thirteen in all, like the Hakem's hand); «دوباره» deals again. The hand is sorted left to right the way the
// game sorts it (suits alternate colors: ♣ ♦ ♠ ♥, each from 2 up to A), and any card can be dragged to a new place.
// Each card is the game's own Standard deck face (assets/cards, e.g. QD.webp), on the same white paper and grey border.
// The five cards in the HTML stay, without the buttons, if this doesn't run.
var SUITS = ["♣", "♦", "♠", "♥"];
var RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"];
var SUIT_FILE = { "♣": "C", "♦": "D", "♠": "S", "♥": "H" };
function cardHtml(r, s) {
  return '<div class="card"><img src="assets/cards/' + r + SUIT_FILE[s] + '.webp" alt="" draggable="false"></div>';
}

(function () {
  if (typeof document === "undefined") return;
  var fan = document.getElementById("fan");
  var ctl = document.getElementById("deal-ctl");
  if (!fan || !ctl) return;
  var pick = ctl.querySelector(".deal-pick"), done = ctl.querySelector(".deal-done");
  var hokmLabel = document.getElementById("deal-hokm");
  var deck = [], hand = [];  // hand: the cards' elements in fan order (not DOM order: moving a node would make it jump)

  function sortKey(el) { return SUITS.indexOf(el.dataset.s) * 13 + RANKS.indexOf(el.dataset.r); }
  function makeCard(c) {
    var t = document.createElement("div");
    t.innerHTML = cardHtml(c.r, c.s);
    var el = t.firstChild;
    el.dataset.r = c.r; el.dataset.s = c.s;
    return el;
  }
  // Spread the fan: one step per card, as wide as fits (--spread, smaller on phones), later cards on top.
  function lay(order) {
    var n = order.length;
    var spread = parseFloat(getComputedStyle(fan).getPropertyValue("--spread")) || 60;
    fan.style.setProperty("--step", (n > 1 ? Math.min(13, spread / (n - 1)) : 0) + "deg");
    order.forEach(function (el, i) {
      el.style.setProperty("--i", i - (n - 1) / 2);
      el.style.zIndex = i + 1;
    });
  }
  // Add cards to the table, dealt in one by one.
  function dealIn(cards) {
    cards.forEach(function (el, k) {
      el.classList.add("deal-in");
      el.style.setProperty("--d", k * 0.07 + "s");
      el.addEventListener("animationend", function () { el.classList.remove("deal-in"); }, { once: true });
      fan.appendChild(el);
    });
  }
  function draw(n) { return deck.splice(0, n).map(makeCard); }

  function start() {
    deck = [];
    SUITS.forEach(function (s) { RANKS.forEach(function (r) { deck.push({ r: r, s: s }); }); });
    for (var i = deck.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = deck[i]; deck[i] = deck[j]; deck[j] = t;
    }
    fan.innerHTML = "";
    hand = draw(5).sort(function (a, b) { return sortKey(a) - sortKey(b); });
    lay(hand);
    dealIn(hand);
    pick.hidden = false; done.hidden = true;
  }
  function callHokm(suit) {
    var more = draw(8);
    hand = hand.concat(more).sort(function (a, b) { return sortKey(a) - sortKey(b); });
    lay(hand);
    dealIn(more);
    hokmLabel.textContent = suit;
    hokmLabel.className = suit === "♥" || suit === "♦" ? "red" : "";
    pick.hidden = true; done.hidden = false;
  }

  ctl.hidden = false;
  ctl.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest("button");
    if (!b) return;
    if (b.dataset.suit) callHokm(b.dataset.suit);
    else if (b.id === "deal-again") start();
  });
  start();

  // Any card can be picked up and dragged, with mouse or finger. The other cards open a gap where it would land,
  // worked out from the pointer's angle around the fan's pivot, and on release it drops into that place.
  if (!window.PointerEvent) return;
  var drag = null;
  function step() { return parseFloat(fan.style.getPropertyValue("--step")) || 0; }
  function slotAt(x, y) {
    var r = fan.getBoundingClientRect();
    var h = drag.card.offsetHeight;
    var cardTop = r.bottom - 10 - h;                         // .fan .card sits 10px above the fan's bottom
    var px = r.left + r.width / 2, py = cardTop + 1.9 * h;  // its transform-origin: 50% 190%
    var angle = Math.atan2(x - px, py - y) * 180 / Math.PI;
    var n = drag.others.length + 1;
    return Math.max(0, Math.min(n - 1, Math.round(angle / (step() || 1) + (n - 1) / 2)));
  }
  fan.addEventListener("pointerdown", function (e) {
    var card = e.target.closest && e.target.closest(".card");
    if (!card || e.button > 0) return;
    e.preventDefault();
    hand.forEach(function (el) { el.classList.remove("deal-in"); });  // the deal animation would override the drag
    drag = {
      card: card, id: e.pointerId, x: e.clientX, y: e.clientY,
      lift: e.pointerType === "mouse" ? -18 : 0,             // a hovered card is already raised 18px
      r: parseFloat(card.style.getPropertyValue("--i")) * step(),
      others: hand.filter(function (el) { return el !== card; }), slot: hand.indexOf(card)
    };
    card.setPointerCapture(e.pointerId);
    card.classList.add("dragging");
  });
  fan.addEventListener("pointermove", function (e) {
    if (!drag || e.pointerId !== drag.id) return;
    drag.card.style.transform = "translate(" + (e.clientX - drag.x) + "px, " + (e.clientY - drag.y + drag.lift) +
      "px) rotate(" + drag.r + "deg)";
    var slot = slotAt(e.clientX, e.clientY);
    if (slot === drag.slot) return;
    drag.slot = slot;
    hand = drag.others.slice();
    hand.splice(slot, 0, drag.card);
    lay(hand);
  });
  function drop(e) {
    if (!drag || e.pointerId !== drag.id) return;
    drag.card.classList.remove("dragging");
    drag.card.style.transform = "";
    drag = null;
  }
  fan.addEventListener("pointerup", drop);
  fan.addEventListener("pointercancel", drop);
})();

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

