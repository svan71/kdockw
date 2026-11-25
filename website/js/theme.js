(() => {
  const key = "kdockw-theme";
  const root = document.documentElement;
  let theme = "system";

  try {
    const saved = localStorage.getItem(key);
    if (saved === "light" || saved === "dark") theme = saved;
  } catch {
    // The selector still works when storage is unavailable.
  }

  root.dataset.theme = theme;

  document.addEventListener("DOMContentLoaded", () => {
    const select = document.getElementById("theme");
    select.value = theme;
    select.closest(".theme-picker").hidden = false;

    select.addEventListener("change", () => {
      root.dataset.theme = select.value;
      try {
        localStorage.setItem(key, select.value);
      } catch {
        // The choice applies for this page even without persistence.
      }
    });
  });
})();
