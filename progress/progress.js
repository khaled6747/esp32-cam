'use strict';
const labels={pending:'لم يبدأ',active:'جارٍ التنفيذ',verified:'تم التحقق',failed:'فشل تحقق',blocked:'بوابة غير متاحة'};
const el=id=>document.getElementById(id);
function renderItems(target,items){
  target.replaceChildren();
  for(const item of items){
    const li=document.createElement('li');li.className=item.state;
    const title=document.createElement('strong');title.textContent=item.title;
    const badge=document.createElement('span');badge.className='badge';badge.textContent=labels[item.state];
    const evidence=document.createElement('div');evidence.className='evidence';evidence.textContent=item.evidence;
    li.append(title,badge,evidence);target.append(li);
  }
}
async function refresh(){
  try{
    const response=await fetch('/state.json',{cache:'no-store',signal:AbortSignal.timeout(2500)});
    if(!response.ok)throw new Error('record unavailable');
    const record=await response.json();
    if(!record.batch||!Array.isArray(record.batch.tasks)||!Array.isArray(record.milestones))throw new Error('invalid record');
    const tasks=record.batch.tasks;
    el('batch-title').textContent=record.batch.title;el('activity').textContent=record.activity;
    el('count').textContent=`تم التحقق من ${tasks.filter(t=>t.state==='verified').length} / ${tasks.length} مهام في هذه الدفعة. ليس نسبة قبول للهاردوير.`;
    renderItems(el('tasks'),tasks);renderItems(el('milestones'),record.milestones);
    el('blockers').replaceChildren();for(const text of record.blockers){const li=document.createElement('li');li.textContent=text;el('blockers').append(li);}
    el('updated').textContent=`آخر تحديث فعلي للسجل: ${record.updated_at}`;
    el('connection').className='online';el('connection').textContent='متصل بالسجل المحلي — الحالات لا تتغير بمرور الوقت';
  }catch(error){
    el('connection').className='offline';el('connection').textContent='غير متصل / السجل غير متاح — المعروض قديم، ولا يُضاف أي تقدم';
  }
}
refresh();setInterval(refresh,3000);
