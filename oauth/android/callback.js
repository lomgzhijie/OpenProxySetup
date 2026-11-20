(() => {
  const callbackPath = '/oauth/android/callback.html';
  const query = new URLSearchParams(location.search);
  const state = query.getAll('state');
  const code = query.getAll('code');
  const error = query.getAll('error');
  if (state.length !== 1 || !/^[\w-]{43}$/.test(state[0])) return;

  const validCode = code.length === 1 && code[0].length > 0 && code[0].length <= 4096 && error.length === 0;
  const denied = code.length === 0 && error.length === 1 && /^[\w-]{1,80}$/.test(error[0]);
  if (!validCode && !denied) return;

  const data = new URLSearchParams({ state: state[0] });
  if (validCode) data.set('code', code[0]);
  else data.set('error', error[0]);

  history.replaceState(null, '', callbackPath);
  const button = document.createElement('a');
  button.className = 'button';
  button.textContent = '返回应用';
  button.href = 'intent://openproxysetup.ccwu.cc' + callbackPath + '?' + data.toString() +
    '#Intent;scheme=https;package=org.openproxysetup;end';
  document.getElementById('return-app').append(button);
  document.getElementById('status').textContent = '点下方按钮回到应用，完成账号验证。';
})();
