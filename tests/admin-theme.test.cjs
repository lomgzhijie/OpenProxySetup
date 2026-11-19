const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const template = fs.readFileSync(require('path').join(__dirname, '../assets/admin-theme.js'), 'utf8');
function render(origin, topFrame, dark) {
  let css = '', touched = false;
  const root = {classList:{toggle(){touched=true}},setAttribute(){},appendChild(){}};
  const doc = {documentElement:root,head:root,getElementById(){return null},
    createElement(){return {set textContent(v){css=v}}},addEventListener(){}};
  const frame = {};
  const window = {top:topFrame ? null : frame}; if (topFrame) window.top=window;
  vm.runInNewContext(template.replace('__OPS_ORIGIN__',JSON.stringify('https://example.test'))
    .replace('__OPS_DARK__',String(dark)), {window,document:doc,location:{origin}});
  return {css,touched};
}
assert(!render('https://other.test',true,true).touched, 'Cross-origin document must be untouched');
assert(!render('https://example.test',false,true).touched, 'Frames must be untouched');
assert(render('https://example.test',true,true).css.includes('#101827'), 'Dark palette');
assert(render('https://example.test',true,false).css.includes('#f1f5fc'), 'Light palette');
console.log('PASS scoped themes, frame exclusion, light and dark palettes');
