// Open Proxy Setup embedded admin appearance. Original site functionality and credits remain intact.
(() => {
  if (window.top !== window || location.origin !== __OPS_ORIGIN__) return;
  const dark = __OPS_DARK__;
  const apply = () => {
    const root = document.documentElement;
    if (!root) return;
    root.classList.toggle('dark-mode', dark);
    root.setAttribute('data-ops-theme', dark ? 'dark' : 'light');
    let style = document.getElementById('ops-app-theme');
    if (!style) {
      style = document.createElement('style'); style.id = 'ops-app-theme';
      (document.head || root).appendChild(style);
    }
    style.textContent = `
      :root,html.dark-mode {
        color-scheme:${dark ? 'dark' : 'light'};
        --admin-bg-base:${dark ? '#101827' : '#f1f5fc'};
        --bg-primary:${dark ? '#19243a' : '#ffffff'};
        --bg-secondary:${dark ? '#22324d' : '#edf3ff'};
        --card-glass:var(--bg-primary);
        --text-primary:${dark ? '#f1f5ff' : '#132442'};
        --text-secondary:${dark ? '#b7c6df' : '#536884'};
        --text-muted:${dark ? '#94a6c3' : '#687c99'};
        --border-color:${dark ? '#384b69' : '#d8e3f6'};
        --border-light:var(--border-color);
        --input-bg:${dark ? '#101a2c' : '#ffffff'};
        --input-border:var(--border-color);
        --overlay-bg:${dark ? 'rgba(16,24,39,.88)' : 'rgba(243,246,252,.9)'};
        --dim-bg:rgba(9,18,34,.6);
        --accent-a:#4c85f7;--accent-b:${dark ? '#385ecf' : '#244bdb'};
        --accent-grad:linear-gradient(135deg,var(--accent-a),var(--accent-b));
        --accent-grad-h:linear-gradient(90deg,var(--accent-a),var(--accent-b),var(--accent-a));
        --focus:#638fff;--focus-ring:rgba(76,133,247,.2);
        --chip-bg:rgba(76,133,247,.13);--chip-text:${dark ? '#b4ceff' : '#2753c9'};
        --shadow-card:0 8px 32px rgba(9,25,58,.08);--icon-glow:0 8px 24px rgba(49,92,223,.2);
      }
      html,body{background:var(--admin-bg-base)!important;color:var(--text-primary)!important;
        font-family:Inter,'Segoe UI','Microsoft YaHei',system-ui,sans-serif!important}
      #background-iframe,.background-iframe{display:none!important}
      .container,.card,.module,.header,.login-container,.settings-section,.section-card,.page-header,.network-card,.modal,
      html.dark-mode .module,html.dark-mode .header {
        background:var(--bg-primary)!important;border-color:var(--border-color)!important;
        border-radius:20px!important;box-shadow:var(--shadow-card)!important}
      .header,html.dark-mode .header{border-image:none!important;border-top:1px solid var(--border-color)!important}
      .header-title h1{background:none!important;-webkit-text-fill-color:var(--text-primary)!important;color:var(--text-primary)!important}
      input,select,textarea{background:var(--input-bg)!important;color:var(--text-primary)!important;
        border-color:var(--input-border)!important;border-radius:12px!important}
      input:focus,select:focus,textarea:focus{outline-color:var(--focus)!important}
      .btn-primary,.copy-btn,.login-btn,button[type=submit],#loginBtn {
        background:var(--accent-grad)!important;color:white!important;border-radius:12px!important}
      a{color:${dark ? '#aac5ff' : '#315cdf'}}
      @media(max-width:600px){body{overflow-wrap:anywhere}.container{margin:12px!important;
        padding:18px!important;width:auto!important;max-width:calc(100% - 24px)!important}}
    `;
  };
  apply();
  if (!document.head) document.addEventListener('DOMContentLoaded', apply, {once:true});
  else document.addEventListener('DOMContentLoaded', apply, {once:true});
})();
