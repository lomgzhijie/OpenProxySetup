(() => {
  const root = document.documentElement;
  const system = matchMedia("(prefers-color-scheme: dark)");
  const labels = {
    "zh-CN": ["外观", "日间模式", "暗夜模式"],
    en: ["Appearance", "Light mode", "Dark mode"],
    ja: ["外観", "ライトモード", "ダークモード"],
    ko: ["화면 모드", "라이트 모드", "다크 모드"]
  };
  let choice;
  try {
    choice = localStorage.getItem("ops-theme");
  } catch {}
  if (choice !== "light" && choice !== "dark") choice = null;

  function applyTheme() {
    const theme = choice || (system.matches ? "dark" : "light");
    root.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]').content = theme === "dark" ? "#101827" : "#f6f8fc";
    const controls = document.querySelector(".theme-controls");
    if (!controls) return;
    const [group, light, dark] = labels[root.lang] || labels.en;
    controls.setAttribute("aria-label", group);
    for (const button of controls.querySelectorAll("[data-set-theme]")) {
      const mode = button.dataset.setTheme;
      const label = mode === "light" ? light : dark;
      button.title = label;
      button.setAttribute("aria-label", label);
      button.setAttribute("aria-pressed", String(mode === theme));
    }
  }

  applyTheme();
  document.addEventListener("DOMContentLoaded", () => {
    applyTheme();
    for (const button of document.querySelectorAll("[data-set-theme]")) {
      button.addEventListener("click", () => {
        choice = button.dataset.setTheme;
        try { localStorage.setItem("ops-theme", choice); } catch {}
        applyTheme();
      });
    }
  });
  system.addEventListener("change", applyTheme);
  new MutationObserver(applyTheme).observe(root, {attributeFilter: ["lang"]});
})();
