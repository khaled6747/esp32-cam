'use strict';
const item = id => document.getElementById(id);
let active = false, serial = 0;
async function update() {
  if (active) return;
  active = true;
  try {
    const response = await fetch('/status', {cache:'no-store', signal:AbortSignal.timeout(2500)});
    if (!response.ok) throw new Error('status unavailable');
    const state = await response.json();
    const fresh = state.connected === true && state.status === 'ready' && Number.isInteger(state.people);
    item('people').textContent = fresh ? state.people : '—';
    item('connection').textContent = fresh ? 'نتيجة حديثة مرتبطة بصورة المصدر' : 'عدد غير معروف — لا يُعامل كصفر';
    item('mode').textContent = state.controller?.mode || '—';
    item('ir').textContent = state.controller?.ir_result || '—';
    item('error').textContent = state.error || '';
    item('frame').hidden = !fresh;
    if (fresh) item('frame').src = `/frame.jpg?${++serial}`;
  } catch (error) {
    item('people').textContent = '—';
    item('connection').textContent = 'الاتصال باللاب متوقف / البيانات قديمة';
    item('frame').hidden = true;
    item('error').textContent = 'لا توجد بيانات حالية؛ راجع نافذة تشغيل الـbridge.';
  } finally { active = false; }
}
item('frame').addEventListener('error', () => { item('frame').hidden = true; });
update(); setInterval(update, 700);
